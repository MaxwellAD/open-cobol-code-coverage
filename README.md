# Open COBOL Code Coverage

Free and open source COBOL Code Coverage library

## How to use

``` bash
./cobol-code-coverage.sh <source file> <output file>
```

The script reads the source file and builds the output file as a mirror with code coverage logic instrumented, which can be then passed onto a compiler of your choosing, I have been using GNU COBOL to test.

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
    TOTAL STATEMENTS: 0019
    COVERED STATEMENTS: 0015
    STATEMENT COVERAGE: 078.94%
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
    TOTAL STATEMENTS: 0019
    COVERED STATEMENTS: 0015
    STATEMENT COVERAGE: 078.94%
****************************************************************************************
    END OF REPORT - CALC                                            
****************************************************************************************
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

### Combining Coverage Statistics
If you are using this to test a bigger COBOL program, chances are you aren't hitting all of your cases in a single instance of the code. You'll need to combine the coverage of multiple runs to get the true number of verbs covered by your testing session

In theory this can be as simple as:
- appending the COV-FLAGS array to a file
- Each execution adds a new record of COV-FLAGS
- Run an OR against every column to get the overall value
- Or SUM every column and all flags greater than zero are covered
- This can easily get you the summary statistics, however re-translating that back into a visual PROCEDURE DIVISION recreation will need some work

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