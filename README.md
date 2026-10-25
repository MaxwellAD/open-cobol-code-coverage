# Open COBOL Code Coverage

<!--
SPDX-License-Identifier: GPL-3.0-or-later
SPDX-FileCopyrightText: 2026 MaxwellAD
-->

Free and open source COBOL Code Coverage library

## How to use

``` bash
./code-coverage-precompiler.sh <source file> <output file>
```

The script reads the source file and builds the output file as a mirror with code coverage logic instrumented, which can be then passed onto a compiler of your choosing, I have been using GNU COBOL to test.

It also writes a second program next to the output file, `<PROGRAM-ID>-combine.cbl`, which merges the coverage of many runs into one report - see [Combining Coverage Across Runs](#combining-coverage-across-runs).

## Example

### Examples/CALC.cbl

#### Normal Output:
```
Enter two numbers: 
7
5
Enter operator (ADD, SUB, MUL, DIV): 
ADD
Result: 00012
```

#### Output With Code Coverage
```
Enter two numbers: 
5
7
Enter operator (ADD, SUB, MUL, DIV): 
ADD
Result: 00012
****************************************************************************************
    COVERAGE REPORT - CALC                                            
****************************************************************************************
           PROCEDURE DIVISION.
           AA-MAIN-PGM.
[+]            PERFORM AB-INITIALISE 
[+]            PERFORM AC-ACCEPT-INPUT 
[+]            PERFORM BA-CALC-PROC
[+]            STOP RUN
               .
    
           AB-INITIALISE.
[+]            MOVE SPACES TO WS-OPERATOR 
[+]            MOVE ZEROS TO RESULT 
[+]            MOVE ZEROS TO NUM1 
[+]            MOVE ZEROS TO NUM2 
           . 
    
           AC-ACCEPT-INPUT.
[+]            DISPLAY "Enter two numbers: "
[+]            ACCEPT NUM1
[+]            ACCEPT NUM2
[+]            DISPLAY "Enter operator (ADD, SUB, MUL, DIV): "
[+]            ACCEPT WS-OPERATOR
           .
    
           BA-CALC-PROC.
               EVALUATE WS-OPERATOR
                   WHEN 'ADD'
[+]                    COMPUTE RESULT = NUM1 + NUM2
                   WHEN 'SUB'
[-]                    COMPUTE RESULT = NUM1 - NUM2
                   WHEN 'MUL'
[-]                    COMPUTE RESULT = NUM1 * NUM2
                   WHEN 'DIV'
[-]                    COMPUTE RESULT = NUM1 / NUM2
                   WHEN OTHER 
[-]                    DISPLAY 'THE OPERATOR WAS NOT VALID'
               END-EVALUATE
[+]            DISPLAY "Result: " RESULT
    
           .
****************************************************************************************
    SUMMARY STATISTICS                           
****************************************************************************************
    TOTAL STATEMENTS: 19
    COVERED STATEMENTS: 15
    STATEMENT COVERAGE: 078.94%
*COV* 0750898251 01 1111111111111100001
****************************************************************************************
    END OF REPORT - CALC                                            
****************************************************************************************
```

If an invalid operator was input then the coverage report would reflect that
```
Enter two numbers: 
5
7
Enter operator (ADD, SUB, MUL, DIV): 
XXXX
THE OPERATOR WAS NOT VALID
Result: 00000
****************************************************************************************
    COVERAGE REPORT - CALC                                            
****************************************************************************************
           PROCEDURE DIVISION.
           AA-MAIN-PGM.
[+]            PERFORM AB-INITIALISE 
[+]            PERFORM AC-ACCEPT-INPUT 
[+]            PERFORM BA-CALC-PROC
[+]            STOP RUN
               .
    
           AB-INITIALISE.
[+]            MOVE SPACES TO WS-OPERATOR 
[+]            MOVE ZEROS TO RESULT 
[+]            MOVE ZEROS TO NUM1 
[+]            MOVE ZEROS TO NUM2 
           . 
    
           AC-ACCEPT-INPUT.
[+]            DISPLAY "Enter two numbers: "
[+]            ACCEPT NUM1
[+]            ACCEPT NUM2
[+]            DISPLAY "Enter operator (ADD, SUB, MUL, DIV): "
[+]            ACCEPT WS-OPERATOR
           .
    
           BA-CALC-PROC.
               EVALUATE WS-OPERATOR
                   WHEN 'ADD'
[-]                    COMPUTE RESULT = NUM1 + NUM2
                   WHEN 'SUB'
[-]                    COMPUTE RESULT = NUM1 - NUM2
                   WHEN 'MUL'
[-]                    COMPUTE RESULT = NUM1 * NUM2
                   WHEN 'DIV'
[-]                    COMPUTE RESULT = NUM1 / NUM2
                   WHEN OTHER 
[+]                    DISPLAY 'THE OPERATOR WAS NOT VALID'
               END-EVALUATE
[+]            DISPLAY "Result: " RESULT
    
           .
****************************************************************************************
    SUMMARY STATISTICS                           
****************************************************************************************
    TOTAL STATEMENTS: 19
    COVERED STATEMENTS: 15
    STATEMENT COVERAGE: 078.94%
*COV* 0750898251 01 1111111111111000011
****************************************************************************************
    END OF REPORT - CALC                                            
****************************************************************************************
```

## Combining Coverage Across Runs

A single run rarely exercises every path, so each report also ends with one or more `*COV*` lines - the raw coverage data for that run:

```
*COV* 0750898251 01 1111111111111100001
      |          |  |
      |          |  flags, one per instrumented statement (1 = executed)
      |          offset of the first flag on this line
      fingerprint of the instrumented program
```

The generated combine program reads captured output from any number of runs, ORs the flags together (a statement is covered if *any* run executed it) and prints the usual report for the whole set. Any other lines in the input are ignored, so a job's SYSOUT, a unit test report or pasted terminal output can be fed in as is.

``` bash
cobc -x CALC-combine.cbl -o calc-combine
COVIN=<(cat run1.txt run2.txt) ./calc-combine
```

The combine program reads `COVIN` - a DD name in JCL, or on UNIX/Linux an environment variable naming the file. Combining the two CALC runs above (one `ADD`, one invalid operator) covers both branches:

```
                   WHEN 'DIV'
[-]                    COMPUTE RESULT = NUM1 / NUM2
                   WHEN OTHER 
[+]                    DISPLAY 'THE OPERATOR WAS NOT VALID'
               END-EVALUATE
...
    TOTAL STATEMENTS: 19
    COVERED STATEMENTS: 16
    STATEMENT COVERAGE: 084.21%
...
    RUNS MERGED: 000000002
    COVERAGE LINES MERGED: 000000002
    COVERAGE LINES SKIPPED (OTHER PROGRAM, STALE OR MALFORMED): 000000000
    INPUT LINES POSSIBLY TRUNCATED: 000000000
```

Things worth knowing:
- **Stale data is rejected.** The fingerprint changes whenever the source (or which statements get instrumented) changes, so output from an older version of the program is counted as skipped rather than merged into the wrong statements.
- **The data goes to DISPLAY, not a file.** That keeps the instrumented program free of file I/O, so it works anywhere DISPLAY does - only the combine program needs to read a file.
- **Line widths can be set.** `COVERAGE_OUTPUT_WIDTH` (default 80) is the widest `*COV*` line the instrumented program writes - set it to the record length of wherever the output lands, so lines are never split. `COVERAGE_INPUT_WIDTH` (default 4096) is the widest line the combine program reads; lines that fill it are reported as possibly truncated.

``` bash
COVERAGE_OUTPUT_WIDTH=133 ./code-coverage-precompiler.sh <source file> <output file>
```

## How It Works

1. Read a raw COBOL source file
2. Output a mirror file line by line
3. Also create a DISPLAY-COVERAGE SECTION that displays the source code
```COBOL
                 DISPLAY "           PROCEDURE DIVISION."
                 DISPLAY "           AA-MAIN-PGM."
```
1. If a line has an "executable" verb (defined in a list), such as MOVE, DISPLAY, COMPUTE, etc. Then instrument a flag to be set 
```COBOL
             MOVE "1" TO COV-FLAGS(1)
           PERFORM AB-INITIALISE 
             MOVE "1" TO COV-FLAGS(2)
           PERFORM AC-ACCEPT-INPUT 
             MOVE "1" TO COV-FLAGS(3)
           PERFORM BA-CALC-PROC
```
1. At the same time, add a condition to the DISPLAY-COVERAGE for that line so a [+] is displayed if it was set and a [-] is displayed if it was not
```COBOL
             IF COV-FLAGS(1) = "1"
                 DISPLAY "[+]            PERFORM AB-INITIALISE "
             ELSE
                 DISPLAY "[-]            PERFORM AB-INITIALISE "
             END-IF
             IF COV-FLAGS(2) = "1"
                 DISPLAY "[+]            PERFORM AC-ACCEPT-INPUT "
             ELSE
                 DISPLAY "[-]            PERFORM AC-ACCEPT-INPUT "
             END-IF
             IF COV-FLAGS(3) = "1"
                 DISPLAY "[+]            PERFORM BA-CALC-PROC"
             ELSE
                 DISPLAY "[-]            PERFORM BA-CALC-PROC"
             END-IF
```
1. Once at the end of the source file, add the required working storage flags and append the DISPLAY-COVERAGE SECTION to the end of the procedure division
1. The DISPLAY-COVERAGE SECTION finishes by displaying the flags themselves as `*COV*` lines, and the same report section is reused in a bespoke combine program that reads those lines back in from many runs


## Why
It's basic, but it works suprisingly well in the few programs I've wrote, even just as a debugger to see which condition a run fell into

I've never created an open source project before, however the lack of open source options has been bugging me and I like the simplicity of this solution

## Improvements
### Execution Trace
The ability to see which lines ran has been very useful as a debugging tool

What if this tool had a "trace mode", instead of displaying which statements ran, display the order in which they ran, making it easier to follow loops

There could be various levels of trace mode, the lowest being every single executable line, next up displaying which conditional paths were taken (IF / EVALUATE), the next level up could be paragraph level, etc

### Outputting To a File
Write a file instead of displaying to STDOUT

### Custom Exit Statements
Currently the script looks for a `GO BACK` or `STOP RUN` for the moment to display the coverage report, I can imagine something more flexible might be valueable, for example displaying the coverage before linking to another module

### Clearing Coverage Statistics
The ability to reset the coverage statistics mid flight may be useful if there's some highly reusable code that you want to evidence in a specific context that only appears deep in some business logic

### Branch Coverage Logic
Verbs are either executed or unexecuted, however conditions can be partially executed, e.g the IF but not the ELSE, or not all branches of an EVALUATE, or not even every permutation that satisfies the IF

`IF A OR B`
- What if you only ever test with A?
- What happens when B is true? 
- What happens when both are true?

If the condition never happens, log the coverage as a [-]
If all permutations are executed, log the coverage as a [+]
But if some permutations are missed, log the IF as a [?] to represent incomplete coverage

## Contributing

Happy for any and all contributions, feel free to get in touch