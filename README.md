 Compare-UserJS
----------------

- [Requirements][2]
- [Instructions][3]
- [Parameters][4]
- [Examples and tips][5]
- [Acknowledgments][6]
- [Glossary][7]
---

This script parses [*user.js* files][7] and compares them, logging the results to *userJS_diff.log*.

Information provided by this script:

- matching prefs, both value and [state][7].
- prefs with different values but matching state.
- prefs declared in file A but not in file B, and vice versa.
- inactive in A but active in B, and vice versa.
- duplicates in each of the two source files.

Additionally, it can catch one type of syntax error (for now), and includes that information in the report.

You can see an example of what the output looks like [here][example].


🔹 Requirements
---------------

PowerShell version 2 (or newer) and .NET 3.5 (or newer), both of which come as standard components of Windows 7, but the script also **runs fine on Unix-like systems**. You can download the latest version of PowerShell and its dependencies from the official [PowerShell repository][ps].

🔹 Instructions
---------------

Compare-UserJS requires two parameters: the paths of the two files to be compared. You can pass them directly from the console/terminal, but that is not strictly necessary because the script will prompt you to enter them during execution if you don't.

If you're on *nix you can just skip to the [examples][5].

On Windows you can:
1. Download copies of both [*Compare-UserJS.bat*][bat] and [*Compare-UserJS.ps1*][ps1].
2. Place them in the same folder.
3. Drag and drop the two files that you want to compare on the *Compare-UserJS.bat*, simultaneously.

The *Compare-UserJS.bat* works as a launcher that makes it easier to run the PowerShell script. If you don't want to use said batchfile, you will first have to either:

...relax the execution policy:
```PowerShell
# pick one or the other
Set-ExecutionPolicy RemoteSigned
Set-ExecutionPolicy Unrestricted
```

...or call the script like this:
```Batchfile
PowerShell -ExecutionPolicy Bypass -File Compare-UserJS.ps1 <params>
```

[:top:][1]


🔹 Parameters
---------------

|**Index** |   **Name**    | **Required?** |    **Default**    |                        **Description**                        |
|:--------:|:-------------:|:-------------:|:-----------------:|---------------------------------------------------------------|
|    0     | `filePath_A`  |      Yes      |                   | Path to the first file to compare. (1)                        |
|    1     | `filePath_B`  |      Yes      |                   | Path to the second file to compare.                           |
|    2     |  `ouputFile`  |      No       | *userJS_diff.log* | Path to the file where the report will be dumped.             |
|    3     |   `append`    |      No       |       false       | Append the report to the end of the file if it already exists.|
|    4     | `noCommentsA` |      No       |       false       | Parse JS comments in file A as code. (deprecated)             |
|    5     | `noCommentsB` |      No       |       false       | Parse JS comments in file B as code.                          |
|    6     |  `hideMask`   |      No       |         0         | Bitmask value for hiding parts of the report selectively. (2) |
|    7     |    `inJS`     |      No       |       false       | Get the report written in JavaScript. (3)                     |

<sub><em>
  1 - All path parameters can be absolute or relative. <br>
  2 - See the embedded help info for details. <br>
  3 - It will be written to userJS_diff.js unless the -outputFile parameter is also specified.
</em></sub>

[:top:][1]


🔹 Examples and tips
--------------------

See the embedded help info:
```PowerShell
Get-Help .\Compare-UserJS -full
```
Or just read it from the file, but that's less thrilling.

If you encounter any sort of issues with this script in a version of PowerShell higher than v2, try forcing the use of PSv2 like this:
```Shell
PowerShell -Version 2 -File Compare-UserJS.ps1 <params>
# if you have PowerShell Core, use "pwsh" instead of "PowerShell", like this:
pwsh -Version 2 -File Compare-UserJS.ps1 <params>
```
---------------

Comparing fileA to fileB:
```PowerShell
.\Compare-UserJS.ps1 "C:\absolute\path\to\fileA" "..\relative\path\to\fileB"
```

Comparing *fileA.js* to *fileB.js*, and saving the report to *report.txt*, appending to the end of the file:
```PowerShell
.\Compare-UserJS.ps1 "fileA.js" "fileB.js" -outputFile "report.txt" -append
```

This tool can help you make manual cleanups of your *prefs.js* too!
```PowerShell
.\Compare-UserJS.ps1 prefs.js user.js -hideMask 502 -inJS
```

Passing any parameters to the BAT is the same, except that you don't need the `.\`
```Batchfile
Compare-UserJS.bat "fileA.js" "fileB.js" -outputFile diff.txt
```

[:top:][1]


🔹 Acknowledgments
-------------------
Thanks to [Thorin-Oakenpants][p] and [earthlng][e] for their valuable feedback on the initial stages of this little project.


🔹 Glossary
-------------
- State: Whether a pref was declared within the context of a JavaScript comment (inactive) or not (active).
- user.js: Configuration file used by Firefox. You can find more information [here][article] and [here][wiki]. In the context of this project, this refers (to a limited extent) to all configuration files sharing the same syntax, including *prefs.js* and *all.js*. I recommend you to check out the [ghacks user.js][g-u.js] if you haven't already.


[1]: https://github.com/claustromaniac/Compare-UserJS#Compare-UserJS
[2]: https://github.com/claustromaniac/Compare-UserJS#-requirements
[3]: https://github.com/claustromaniac/Compare-UserJS#-instructions
[4]: https://github.com/claustromaniac/Compare-UserJS#-parameters
[5]: https://github.com/claustromaniac/Compare-UserJS#-examples-and-tips
[6]: https://github.com/claustromaniac/Compare-UserJS#-acknowledgments
[7]: https://github.com/claustromaniac/Compare-UserJS#-glossary

[article]: https://developer.mozilla.org/en-US/docs/Mozilla/Preferences/A_brief_guide_to_Mozilla_preferences
[bat]: https://raw.githubusercontent.com/claustromaniac/Compare-UserJS/master/Compare-UserJS.bat
[example]: https://gist.github.com/claustromaniac/f88116f8a59042d59edf10646c906c24
[g-u.js]: https://github.com/ghacksuserjs/ghacks-user.js
[ps1]: https://raw.githubusercontent.com/claustromaniac/Compare-UserJS/master/Compare-UserJS.ps1
[ps]: https://github.com/PowerShell/PowerShell
[wiki]: https://github.com/ghacksuserjs/ghacks-user.js/wiki/1.1-Overview#small_orange_diamond-what-is-it-what-does-it-do-and-why-would-i-want-one

[p]: https://github.com/Thorin-Oakenpants
[e]: https://github.com/earthlng
