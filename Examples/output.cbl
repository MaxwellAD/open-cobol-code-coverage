      * THIS IS THE PRECOMPILER OUTPUT OF CALC.cbl
      * THIS IS WHAT YOUR OUTPUT SHOULD LOOK LIKE IF DONE CORRECTLY
       IDENTIFICATION DIVISION.
       PROGRAM-ID. CALC.

       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.

       DATA DIVISION.
        WORKING-STORAGE SECTION.
        01 COV-FLAGS OCCURS 19 TIMES PIC 9(1) VALUE 0.
        01 COV-STATS.
          05 TOTAL-STMT       PIC 9(4) VALUE 19.
          05 COVERED-STMT     PIC 9(4) VALUE 0.
          05 PERCENT-CALC     PIC 9(3)V99 VALUE 0.
          05 COV-FLAGS-COUNTER PIC 9(9) COMP VALUE 1.
       01 WS-OPERATOR PIC X(3).
       01 RESULT      PIC 9(5).
       01 NUM1        PIC 9(5).
       01 NUM2        PIC 9(5).

       PROCEDURE DIVISION.
       AA-MAIN-PGM.
             MOVE "1" TO COV-FLAGS(1)
           PERFORM AB-INITIALISE 
             MOVE "1" TO COV-FLAGS(2)
           PERFORM AC-ACCEPT-INPUT 
             MOVE "1" TO COV-FLAGS(3)
           PERFORM BA-CALC-PROC
             MOVE "1" TO COV-FLAGS(4)
            PERFORM DISPLAY-COVERAGE
           STOP RUN
           .

       AB-INITIALISE.
             MOVE "1" TO COV-FLAGS(5)
           MOVE SPACES TO WS-OPERATOR 
             MOVE "1" TO COV-FLAGS(6)
           MOVE ZEROS TO RESULT 
             MOVE "1" TO COV-FLAGS(7)
           MOVE ZEROS TO NUM1 
             MOVE "1" TO COV-FLAGS(8)
           MOVE ZEROS TO NUM2 
       . 

       AC-ACCEPT-INPUT.
             MOVE "1" TO COV-FLAGS(9)
           DISPLAY "Enter two numbers: "
             MOVE "1" TO COV-FLAGS(10)
           ACCEPT NUM1
             MOVE "1" TO COV-FLAGS(11)
           ACCEPT NUM2
             MOVE "1" TO COV-FLAGS(12)
           DISPLAY "Enter operator (ADD, SUB, MUL, DIV): "
             MOVE "1" TO COV-FLAGS(13)
           ACCEPT WS-OPERATOR
       .

       BA-CALC-PROC.
           EVALUATE WS-OPERATOR
               WHEN 'ADD'
             MOVE "1" TO COV-FLAGS(14)
                   COMPUTE RESULT = NUM1 + NUM2
               WHEN 'SUB'
             MOVE "1" TO COV-FLAGS(15)
                   COMPUTE RESULT = NUM1 - NUM2
               WHEN 'MUL'
             MOVE "1" TO COV-FLAGS(16)
                   COMPUTE RESULT = NUM1 * NUM2
               WHEN 'DIV'
             MOVE "1" TO COV-FLAGS(17)
                   COMPUTE RESULT = NUM1 / NUM2
               WHEN OTHER 
             MOVE "1" TO COV-FLAGS(18)
                   DISPLAY 'THE OPERATOR WAS NOT VALID'
           END-EVALUATE
             MOVE "1" TO COV-FLAGS(19)
           DISPLAY "Result: " RESULT

       .
        DISPLAY-COVERAGE SECTION.
             DISPLAY "***********************************************" &
            "*****************************************"
             DISPLAY "    COVERAGE REPORT - CALC                     " &
            "                       "
             DISPLAY "***********************************************" &
            "*****************************************"
                 DISPLAY "           PROCEDURE DIVISION."
                 DISPLAY "           AA-MAIN-PGM."
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
             IF COV-FLAGS(4) = "1"
                 DISPLAY "[+]            STOP RUN"
             ELSE
                 DISPLAY "[-]            STOP RUN"
             END-IF
                 DISPLAY "               ."
                 DISPLAY "    "
                 DISPLAY "           AB-INITIALISE."
             IF COV-FLAGS(5) = "1"
                 DISPLAY "[+]            MOVE SPACES TO WS-OPERATOR "
             ELSE
                 DISPLAY "[-]            MOVE SPACES TO WS-OPERATOR "
             END-IF
             IF COV-FLAGS(6) = "1"
                 DISPLAY "[+]            MOVE ZEROS TO RESULT "
             ELSE
                 DISPLAY "[-]            MOVE ZEROS TO RESULT "
             END-IF
             IF COV-FLAGS(7) = "1"
                 DISPLAY "[+]            MOVE ZEROS TO NUM1 "
             ELSE
                 DISPLAY "[-]            MOVE ZEROS TO NUM1 "
             END-IF
             IF COV-FLAGS(8) = "1"
                 DISPLAY "[+]            MOVE ZEROS TO NUM2 "
             ELSE
                 DISPLAY "[-]            MOVE ZEROS TO NUM2 "
             END-IF
                 DISPLAY "           . "
                 DISPLAY "    "
                 DISPLAY "           AC-ACCEPT-INPUT."
             IF COV-FLAGS(9) = "1"
                 DISPLAY '[+]            DISPLAY "Enter two numbers: ' &
            '"'
             ELSE
                 DISPLAY '[-]            DISPLAY "Enter two numbers: ' &
            '"'
             END-IF
             IF COV-FLAGS(10) = "1"
                 DISPLAY "[+]            ACCEPT NUM1"
             ELSE
                 DISPLAY "[-]            ACCEPT NUM1"
             END-IF
             IF COV-FLAGS(11) = "1"
                 DISPLAY "[+]            ACCEPT NUM2"
             ELSE
                 DISPLAY "[-]            ACCEPT NUM2"
             END-IF
             IF COV-FLAGS(12) = "1"
                 DISPLAY '[+]            DISPLAY "Enter operator (ADD' &
            ', SUB, MUL, DIV): "'
             ELSE
                 DISPLAY '[-]            DISPLAY "Enter operator (ADD' &
            ', SUB, MUL, DIV): "'
             END-IF
             IF COV-FLAGS(13) = "1"
                 DISPLAY "[+]            ACCEPT WS-OPERATOR"
             ELSE
                 DISPLAY "[-]            ACCEPT WS-OPERATOR"
             END-IF
                 DISPLAY "           ."
                 DISPLAY "    "
                 DISPLAY "           BA-CALC-PROC."
                 DISPLAY "               EVALUATE WS-OPERATOR"
                 DISPLAY "                   WHEN 'ADD'"
             IF COV-FLAGS(14) = "1"
                 DISPLAY "[+]                    COMPUTE RESULT = NUM" &
            "1 + NUM2"
             ELSE
                 DISPLAY "[-]                    COMPUTE RESULT = NUM" &
            "1 + NUM2"
             END-IF
                 DISPLAY "                   WHEN 'SUB'"
             IF COV-FLAGS(15) = "1"
                 DISPLAY "[+]                    COMPUTE RESULT = NUM" &
            "1 - NUM2"
             ELSE
                 DISPLAY "[-]                    COMPUTE RESULT = NUM" &
            "1 - NUM2"
             END-IF
                 DISPLAY "                   WHEN 'MUL'"
             IF COV-FLAGS(16) = "1"
                 DISPLAY "[+]                    COMPUTE RESULT = NUM" &
            "1 * NUM2"
             ELSE
                 DISPLAY "[-]                    COMPUTE RESULT = NUM" &
            "1 * NUM2"
             END-IF
                 DISPLAY "                   WHEN 'DIV'"
             IF COV-FLAGS(17) = "1"
                 DISPLAY "[+]                    COMPUTE RESULT = NUM" &
            "1 / NUM2"
             ELSE
                 DISPLAY "[-]                    COMPUTE RESULT = NUM" &
            "1 / NUM2"
             END-IF
                 DISPLAY "                   WHEN OTHER "
             IF COV-FLAGS(18) = "1"
                 DISPLAY "[+]                    DISPLAY 'THE OPERATO" &
            "R WAS NOT VALID'"
             ELSE
                 DISPLAY "[-]                    DISPLAY 'THE OPERATO" &
            "R WAS NOT VALID'"
             END-IF
                 DISPLAY "               END-EVALUATE"
             IF COV-FLAGS(19) = "1"
                 DISPLAY '[+]            DISPLAY "Result: " RESULT'
             ELSE
                 DISPLAY '[-]            DISPLAY "Result: " RESULT'
             END-IF
                 DISPLAY "    "
                 DISPLAY "           ."
            MOVE 0 TO COVERED-STMT
            PERFORM VARYING COV-FLAGS-COUNTER FROM 1 BY 1 
            UNTIL COV-FLAGS-COUNTER > TOTAL-STMT
                IF COV-FLAGS(COV-FLAGS-COUNTER) = "1"
                    ADD 1 TO COVERED-STMT END-IF 
            END-PERFORM
            COMPUTE PERCENT-CALC = 
            (COVERED-STMT / TOTAL-STMT) * 100
             DISPLAY '***********************************************' &
            '*****************************************'
             DISPLAY "    SUMMARY STATISTICS                         " &
            "  "
             DISPLAY '***********************************************' &
            '*****************************************'

             DISPLAY "    TOTAL STATEMENTS: " TOTAL-STMT
             DISPLAY "    COVERED STATEMENTS: ", COVERED-STMT
             DISPLAY "    STATEMENT COVERAGE: ", PERCENT-CALC "%"
             DISPLAY "***********************************************" &
            "*****************************************"
             DISPLAY "    END OF REPORT - CALC                       " &
            "                     "
             DISPLAY "***********************************************" &
            "*****************************************"
             DISPLAY " "
             DISPLAY " "
             DISPLAY " "
             DISPLAY " "
             .
