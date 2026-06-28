       IDENTIFICATION DIVISION.
       PROGRAM-ID. CALC.

       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.

       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01 WS-OPERATOR PIC X(3).
       01 RESULT      PIC 9(5).
       01 NUM1        PIC 9(5).
       01 NUM2        PIC 9(5).

       PROCEDURE DIVISION.
       AA-MAIN-PGM.
           PERFORM AB-INITIALISE 
           PERFORM AC-ACCEPT-INPUT 
           PERFORM BA-CALC-PROC
           STOP RUN
           .

       AB-INITIALISE.
           MOVE SPACES TO WS-OPERATOR 
           MOVE ZEROS TO RESULT 
           MOVE ZEROS TO NUM1 
           MOVE ZEROS TO NUM2 
       . 

       AC-ACCEPT-INPUT.
           DISPLAY "Enter two numbers: "
           ACCEPT NUM1
           ACCEPT NUM2
           DISPLAY "Enter operator (ADD, SUB, MUL, DIV): "
           ACCEPT WS-OPERATOR
       .

       BA-CALC-PROC.
           EVALUATE WS-OPERATOR
               WHEN 'ADD'
                   COMPUTE RESULT = NUM1 + NUM2
               WHEN 'SUB'
                   COMPUTE RESULT = NUM1 - NUM2
               WHEN 'MUL'
                   COMPUTE RESULT = NUM1 * NUM2
               WHEN 'DIV'
                   COMPUTE RESULT = NUM1 / NUM2
               WHEN OTHER 
                   DISPLAY 'THE OPERATOR WAS NOT VALID'
           END-EVALUATE
           DISPLAY "Result: " RESULT

       .
