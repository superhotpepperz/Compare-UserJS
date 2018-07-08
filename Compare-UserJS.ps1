<#
.SYNOPSIS
	Compares two user.js files (for Firefox profiles) and returns all of the differences found between them.

.DESCRIPTION
	Compare-UserJS parses JS files rudimentarily, in search for the specific set of valid expressions used to define preference values in user.js. Said expressions are the following three JavaScript function calls:

	pref("prefname", value);
	user_pref("prefname", value);
	sticky_pref("prefname", value);

	In spite of the fact that it does this natively, Compare-UserJS is still capable of interpreting those three expressions in various valid syntactic forms, like using single quotes instead of double quotes, using space characters, line breaks, etc. Some edge cases may not be supported, however.

	Compare-UserJS can also detect a particular type of syntax error. Specifically, it performs rudimentary (crappy) type-checking on the value parameter of the aforementioned JS function calls. Whenever it seems that the value is neither a string, nor an integer, nor a boolean, Compare-UserJS will include this information in the report.

.PARAMETER filepath_A
	Path of the first file to be used in the comparison. Wildcards are allowed.

.PARAMETER filepath_B
	Path of the second file to be used in the comparison. Wildcards are allowed.

.PARAMETER outputFile
	Path of the file where the report will be dumped. Defaults to 'userJS_diff.log' (relative path).

.PARAMETER append
	Append the report to the end of the file, instead of rewriting if a file by that name exists.

.PARAMETER noCommentsA
	Skips parsing comments in file A, treating everything as active. Useful for making parsing faster when you know beforehand that file A does not have comments.

.PARAMETER noCommentsB
	Skips parsing comments in file B, treating everything as active. Useful for making parsing faster when you know beforehand that file B does not have comments.

.PARAMETER hideMask
	Bitmask value for hiding parts of the report selectively. Adding up the values omits different combinations of the output in the report.
	0 - hide nothing (default)
	1 - hide list of prefs with matching values and matching state (active/inactive)
	2 - hide list of prefs with different values
	4 - hide list of prefs declared in A but not in B
	8 - hide list of prefs declared in B but not in A
	16 - hide list of matching prefs active in A but inactive in B
	32 - hide list of matching prefs active in B but inactive in A
	64 - hide list of prefs that have both mismatching values and states
	128 - hide potential syntax errors

.NOTES
	Version: 1.4.1
	Update Date: 2018-07-06
	Release Date: 2018-06-30
	Author: claustromaniac
	Copyright (C) 2018. Released under the MIT license.

.EXAMPLE
	Compare-UserJS "user.js" "C:\temp\user_b.js"

	Compares user.js to user_b.js.

.EXAMPLE
	Compare-UserJS -outputfile "myfile.txt"

	Writes the output to myfile.txt.

.EXAMPLE
	Compare-UserJS -hideMask 5

	Avoids writing to the logfile both the list of matching prefs and the list of prefs not declared in file B.

.EXAMPLE
	Compare-UserJS *.js *.txt

	Loads all JS files in the working directory as one file and compares it with all TXT files in the same directory.

#>
#Requires -Version 2

[CmdletBinding()]

PARAM (
	[Parameter(Mandatory=$True,HelpMessage="Insert the path to the first file to compare.")]
	[ValidateNotNullOrEmpty()]
	[string]$filepath_A,

	[Parameter(Mandatory=$True,HelpMessage="Insert the path to the second file to compare.")]
	[ValidateNotNullOrEmpty()]
	[string]$filepath_B,

	[string]$outputFile = 'userJS_diff.log',
	[Switch]$append = $false,
	[Switch]$noCommentsA = $false,
	[Switch]$noCommentsB = $false,

	[uint32]$hideMask = 0
)
#----------------[ Declarations ]------------------------------------------------------

# Set Error Action, mostly for debugging
$ErrorActionPreference = "Stop"

# Newline characters to use in the logfile, based on OS (CR+LF on Windows, LF everywhere else)
if ($Env:OS) {$nl = "`r`n"} else {$nl = "`n"}

# Create root hash tables for prefs in each file.
$prefsA = @{}
$prefsB = @{}

# Extract the names of the files.
$fileNameA = (Split-Path $filepath_A -leaf)
$fileNameB = (Split-Path $filepath_B -leaf)

if ($fileNameA -ceq $fileNameB) {
	$fileNameA = $filepath_A
	$fileNameB = $filepath_B
}

# Used for padding the output in a few lists.
if ($fileNameA.length -ge $fileNameB.length) {
	$fn_pad = $fileNameA.length
} else {
	$fn_pad = $fileNameB.length
}

# Regular expression for detecting JS comments. Meant to be used as a suffix.
$rx_c = "(?!(?:(?:[^""]|(?<=\\)"")*?""|(?:[^']|(?<=\\)')*?')\s*\)\s*;)"
# Regular expression for matching prefname or value string. Must be used within groups.
$rx_s = "(?:""(?:[^""]|(?<=\\)"")*"")|(?:'(?:[^']|(?<=\\)')*')"
# Regular expression for capturing prefname or value string. Includes two capturing groups.
$rx_sc = "(?:(?:""((?:[^""]|(?<=\\)"")*)"")|(?:'((?:[^']|(?<=\\)')*)'))"

#----------------[ Functions ]---------------------------------------------------------

# Function for parsing pref declarations, extracting prefnames and values, populating the root hashtables.
Function Get-UserJSPrefs {
	Param([hashtable]$prefs_ht, [string]$fileStr, [string]$inactive_flag = "[i]")

	# Semicolons signify the end of a statement in JS. Let's split lines at semicolons, just in case.
	$fileStr = ($fileStr -creplace "(?<=pref\(.{5,}\).*?);", ";`n")

	# Read line by line, filtered.
	ForEach ($line in $fileStr.Split("`n") -cmatch "pref\s*\(\s*['""].*['""]\s*,.*\)\s*;") {
		$prefname = ($line -creplace ("^.*pref\s*\(\s*" + $rx_sc + "\s*,.*\)\s*;.*"), '$1$2')
		if ($prefname -ceq $line) {Continue}
		$val = ($line -creplace ("^.*pref\s*\(\s*(?:" + $rx_s + ")\s*,\s*(?:(?:" + $rx_sc + ")|(true|false|-?[0-9]+))\s*\)\s*;.*"), '$1$2$3')
		$broken = ($val -ceq $line)
		if ($broken) {
			$val = ($line -creplace ("^.*pref\s*\(\s*(?:" + $rx_s + ")\s*,(.*?)\)\s*;.*"), '$1')
		} elseif (!($val -cmatch "^(?:true|false|-?[0-9]+)$")) {$val = '"' + $val + '"'}
		$prefs_ht.$prefname = @{"inactive"=$inactive_flag; "broken"=$broken; "value"=$val}
	}
}

# Function for filtering prefs declared behind single-line JS comments (//...)
Function Read-SLCom {
	Param([hashtable]$prefs_ht, [string]$fileStr)

	# Get only lines with single-line comments
	$fileStr = (($fileStr.Split("`n") -cmatch ("//" + $rx_c)) | Out-String)
	# Trim everything before //
	$fileStr = ($fileStr -creplace ("^.*?" + "//" + $rx_c), "//")
	# Split up lines at // just in case
	$fileStr = ($fileStr -creplace ("//" + $rx_c), "`n")

	Get-UserJSPrefs $prefs_ht $fileStr
}

# Function for filtering prefs declared within the context of JS multi-line comments (/*...*/)
Function Read-MLCom {
	Param([hashtable]$prefs_ht, [string]$fileStr)

	# Trim text between multi-line comments
	$fileStr = ($fileStr -creplace ("(?s)" + "\*/" + $rx_c + ".*?/\*" + $rx_c), "*/`n/*")
	# remove leading text
	$fileStr = ($fileStr -creplace ("(?s)^.*?" + "/\*" + $rx_c), "/*")
	# remove trailing text
	$fileStr = ($fileStr -creplace ("(?s)^(.*" + "\*/" + $rx_c + ").*$"), '$1')
	# Remove single-line comments
	$fileStr = ($fileStr -creplace ("//" + $rx_c + ".*"), "`n")

	Get-UserJSPrefs $prefs_ht $fileStr
}

# Function for filtering active prefs
Function Read-ActivePrefs {
	Param([hashtable]$prefs_ht, [string]$fileStr, [bool]$comments = $true)

	if ($comments) {
		# Remove multi-line comments
		$fileStr = ($fileStr -creplace ("(?s)" + "/\*" + $rx_c + ".*?" + "\*/" + $rx_c), "`n")
		# Remove single-line comments
		$fileStr = ($fileStr -creplace ("//" + $rx_c + ".*"), "`n")
	}

	Get-UserJSPrefs $prefs_ht $fileStr ""
}

# Function for comparing the hashtables and dumping the report data
Function Write-Report {
	Param()

	$unique_prefs = (($prefsA.keys + $prefsB.keys | Sort-Object) | Get-Unique)
	
	# Get the longest prefname, which will be used for padding the output.
	ForEach ($prefname in $unique_prefs)
	{
		if ($pn_pad -lt $prefname.length) {$pn_pad = $prefname.length}
	}
	
	# Format for padding
	$list_format = "{0, -3} {1, " + (-$pn_pad) + "}  {2, 1}" + $nl
	$dlist_format = "{0, -7} {1, " + (-($fn_pad + 3)) + "}  {2, 1}" + $nl
	$summary_format = "{0, 5} {1, -1}"

	# Report chunks, to be formatted as multi-line strings (lists)
	$matching_prefs = ""			# matching pref values
	$differences = ""			# different-value prefs
	$missing_in_A = ""			# missing in file A
	$missing_in_B = ""			# missing in file B
	$inactive_in_A = ""			# matching value but inactive in A
	$inactive_in_B = ""			# matching value but inactive in B
	$fully_mismatching = ""			# different state and value
	$bad_syntax_A = ""			# possible syntax errors in A
	$bad_syntax_B = ""			# blah blah in B

	":::::::::::: { Compare-UserJS Report } ::::::::::::"
	Get-Date
	$nl + "  Summary:"
	$summary_format -f $prefsA.count, ("unique prefs in " + $fileNameA)
	($summary_format -f $prefsB.count, ("unique prefs in " + $fileNameB)) + $nl
	
	ForEach ($prefname in $unique_prefs) {
		$format_arA = @($prefsA.$prefname."inactive", $prefname, [string]$prefsA.$prefname."value")
		$format_arB = @($prefsB.$prefname."inactive", $prefname, [string]$prefsB.$prefname."value")
		if ($prefsA.$prefname -and $prefsB.$prefname) {
			if ($prefsA.$prefname."inactive" -ne $prefsB.$prefname."inactive") {
				if ($prefsA.$prefname."value" -ceq $prefsB.$prefname."value") {
					if ($prefsA.$prefname."inactive") {
						$inactive_in_A += $list_format -f $format_arB
					} else {$inactive_in_B += $list_format -f $format_arA}
				} else {
					$fully_mismatching += ($list_format -f "", $prefname, "") +
						($dlist_format -f @($prefsA.$prefname."inactive", $fileNameA, $prefsA.$prefname."value")) +
						($dlist_format -f @($prefsB.$prefname."inactive", $fileNameB, $prefsB.$prefname."value"))
				}
			} elseif ($prefsA.$prefname."value" -ceq $prefsB.$prefname."value") {
				$matching_prefs += $list_format -f $format_arA
			} else {
				$temp = $format_arA
				$temp[2] = ""
				$differences += ($list_format -f $temp) +
					($dlist_format -f @("", $fileNameA, $prefsA.$prefname."value")) +
					($dlist_format -f @("", $fileNameB, $prefsB.$prefname."value"))
			}
		} elseif ($prefsA.$prefname) {
			$missing_in_B += $list_format -f $format_arA
		} else {$missing_in_A += $list_format -f $format_arB}
		if ($prefsA.$prefname."broken") {$bad_syntax_A += $list_format -f $format_arA}
		if ($prefsB.$prefname."broken") {$bad_syntax_B += $list_format -f $format_arB}
	}

	if ($matching_prefs) {
		$matches_count = ($matching_prefs.Split("`n").count - 1)
		$summary_format -f $matches_count, "matching prefs, both value and state (active/inactive)"
	}
	if ($differences) {
		$diffs_count = (($differences.Split("`n").count - 1) / 3)
		$summary_format -f $diffs_count, "prefs with different values but matching state"
	}
	if ($missing_in_A) {
		$missing_A_count = ($missing_in_A.Split("`n").count - 1)
		$summary_format -f $missing_A_count, ("prefs not declared in " + $fileNameA)
	}
	if ($missing_in_B) {
		$missing_B_count = ($missing_in_B.Split("`n").count - 1)
		$summary_format -f $missing_B_count, ("prefs not declared in " + $fileNameB)
	}
	if ($inactive_in_A) {
		$inactive_A_count = ($inactive_in_A.Split("`n").count - 1)
		$summary_format -f $inactive_A_count, ("prefs with matching values but inactive in " + $fileNameA)
	}
	if ($inactive_in_B) {
		$inactive_B_count = ($inactive_in_B.Split("`n").count - 1)
		$summary_format -f $inactive_B_count, ("prefs with matching values but inactive in " + $fileNameB)
	}
	if ($fully_mismatching) {
		$fm_count = ($fully_mismatching.Split("`n").count - 1) / 3
		$summary_format -f $fm_count, ("prefs with both mismatching values and states")
	}
	" ----"
	$summary_format -f $unique_prefs.count, "combined unique prefs"

	if ($bad_syntax_A -or $bad_syntax_B) {$nl + " Warning:" + $nl}
	if ($bad_syntax_A) {
		$errors_A_count = ($bad_syntax_A.Split("`n").count - 1)
		$summary_format -f $errors_A_count, ("prefs in " + $fileNameA + " seem to have broken values")
	}
	if ($bad_syntax_B) {
		$errors_B_count = ($bad_syntax_B.Split("`n").count - 1)
		$summary_format -f $errors_B_count, "prefs in " + $fileNameB + " seem to have broken values"
	}

	$nl + " Reference: [i] = inactive pref (commented-out)" + $nl

	$sep = "------------------------------------------------------------------------------" + $nl
	if ($matching_prefs -and !($hideMask -band 1)) {$sep + " The following " + $matches_count + " prefs match in both value and state:" + $nl+$nl + $matching_prefs + $nl}
	if ($differences -and !($hideMask -band 2)) {$sep + " The following " + $diffs_count + " prefs have different values, but matching state:" + $nl+$nl + $differences + $nl}
	if ($missing_in_A -and !($hideMask -band 4)) {$sep + " The following " + $missing_A_count + " prefs are not declared in " + $fileNameA + ":" + $nl+$nl + $missing_in_A + $nl}
	if ($missing_in_B -and !($hideMask -band 8)) {$sep + " The following " + $missing_B_count + " prefs are not declared in " + $fileNameB + ":" + $nl+$nl + $missing_in_B + $nl}
	if ($inactive_in_A -and !($hideMask -band 16)) {$sep + " The following " + $inactive_A_count + " prefs match but are inactive in " + $fileNameA + ":" + $nl+$nl + $inactive_in_A + $nl}
	if ($inactive_in_B -and !($hideMask -band 32)) {$sep + " The following " + $inactive_B_count + " prefs match but are inactive in " + $fileNameB + ":" + $nl+$nl + $inactive_in_B + $nl}
	if ($fully_mismatching -and !($hideMask -band 64)) {$sep + " The following " + $fm_count + " prefs have both mismatching values and states:" + $nl+$nl + $fully_mismatching + $nl}
	if ($bad_syntax_A -and !($hideMask -band 128)) {$sep + " " + $errors_A_count + " possible syntax errors detected in " + $fileNameA + ":" + $nl+$nl + $bad_syntax_A + $nl}
	if ($bad_syntax_B -and !($hideMask -band 128)) {$sep + " " + $errors_B_count + " possible syntax errors detected in " + $fileNameB + ":" + $nl+$nl + $bad_syntax_B + $nl}
}

#----------------[ Main Execution ]----------------------------------------------------

# Load files into memory.
Write-Host "Loading" $fileNameA "..."
$fileA = (Get-Content $filepath_A | Out-String)
Write-Host "Loading" $fileNameB "..."
$fileB = (Get-Content $filepath_B | Out-String)

# Remove carriage returns, if they exist. The source files aren't supposed to have them in the first place.
$fileA = $fileA -creplace "`r", ''
$fileB = $fileB -creplace "`r", ''

# Remove unnecessary space and new-line characters within the target JS expressions.
$fileA = ($fileA -creplace ("(?s)pref\s*\(\s*" + $rx_sc + "\s*,\s*(.+?)\s*\)\s*;"), 'pref("$1$2",$3);')
$fileB = ($fileB -creplace ("(?s)pref\s*\(\s*" + $rx_sc + "\s*,\s*(.+?)\s*\)\s*;"), 'pref("$1$2",$3);')

# Parse files
Write-Host "Parsing" $fileNameA "..."
if (!$noCommentsA) {
	Read-SLCom $prefsA $fileA
	Read-MLCom $prefsA $fileA
	Read-ActivePrefs $prefsA $fileA $true
} else {
	Write-Host "Comments in this file will not be parsed as such."
	Read-ActivePrefs $prefsA $fileA $false
}
Write-Host "Parsing" $fileNameB "..."
if (!$noCommentsB) {
	Read-SLCom $prefsB $fileB
	Read-MLCom $prefsB $fileB
	Read-ActivePrefs $prefsB $fileB $true
} else {
	Write-Host "Comments in this file will not be parsed as such."
	Read-ActivePrefs $prefsB $fileB $false
}
Write-Host "Writing report to" $outputFile "..."
if ($append) {
	Write-Report | Out-File $outputFile -append
} else { Write-Report | Out-File $outputFile }
$prompt = Read-Host "All done. Would you like to open the logfile with the default editor? (y/n)"
if ($prompt -eq "y") {Invoke-Item $outputFile}