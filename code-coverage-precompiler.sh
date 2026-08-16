#!/bin/bash

# Copyright (C) 2026 MaxwellAD

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# ==============================================================================
# Phase 1: Initialization & function definition
# Get source and output file paths from CLI arguments.
# ==============================================================================
SOURCE_FILE=$1
OUTPUT_FILE=$2

AREA_A_INDENT="       "
AREA_B_INDENT="            "

# Used when trying to write long dislplay lines
cobol_wrap_display() {
    local input_line="$1"
    local q_char="$2"

    # If the line is short enough, print it as-is
    if [[ ${#input_line} -le 72 ]]; then
        echo "$input_line"
        return
    fi

    # Check if the line is a DISPLAY statement containing quotes
    if [[ "$input_line" =~ DISPLAY[[:space:]]+\'([^\']*)\' ]] || \
       [[ "$input_line" =~ DISPLAY[[:space:]]+\"([^\"]*)\" ]]; then
        
        
        # 2. Extract the prefix (e.g., "            DISPLAY ")
        local prefix="${input_line%%$q_char*}"
        
        # 3. Extract the literal text inside the quotes
        local literal_content="${input_line#*$q_char}"
        literal_content="${literal_content%$q_char*}"

        # 4. Extract any trailing tokens (like a period ".")
        local suffix="${input_line##*$q_char}"

        # Safe splitting size for the first line to leave room for the closing quote and " &"
        # 72 max - prefix length - 4 characters for [quote + space + ampersand + space]
        local first_chunk_max=$((72 - ${#prefix} - 4))
        
        local first_chunk="${literal_content:0:$first_chunk_max}"
        local remaining="${literal_content:$first_chunk_max}"

        # Output the first line properly closed and concatenated with &
        echo "${prefix}${q_char}${first_chunk}${q_char} &"

        # 5. Process remaining text into chunks
        while [[ ${#remaining} -gt 0 ]]; do
            # Max text size per intermediate line: 54 characters
            # (Allows 12 spaces of Area B indentation + quote + text + quote + " &")
            local chunk_size=54
            
            # If it's the last chunk, wrap it up with the final suffix period
            if [[ ${#remaining} -le $chunk_size ]]; then
                printf "            %s%s%s%s\n" "${q_char}" "${remaining}" "${q_char}" "${suffix}"
                remaining=""
            else
                local chunk="${remaining:0:$chunk_size}"
                printf "            %s%s%s &\n" "${q_char}" "${chunk}" "${q_char}"
                remaining="${remaining:$chunk_size}"
            fi
        done
    else
        # For non-DISPLAY long lines, fall back to standard code continuation
        echo "${input_line:0:72}"
        local remaining="${input_line:72}"
        while [[ ${#remaining} -gt 0 ]]; do
            local chunk="${remaining:0:61}"
            printf "      -%-4s%s\n" "" "$chunk"
            remaining="${remaining:61}"
        done
    fi
}


if [[ -z "$SOURCE_FILE" || -z "$OUTPUT_FILE" ]]; then
    echo "Usage: $0 <source_file> <output_file>"
    exit 1
fi

# Read all lines of the source file into an array
mapfile -t SOURCE_FILE_LINES < "$SOURCE_FILE"

# Get starting index of the procedure division
for i in "${!SOURCE_FILE_LINES[@]}"; do
    if [[ "${SOURCE_FILE_LINES[$i]}" == *"PROCEDURE DIVISION"* ]]; then
        PROCEDURE_DIVISION_INDEX=$i
        break
    fi
done

# Re-evaluating the loop to strictly match pseudocode logic for "PROCEDURE DIVISION"
for i in "${!SOURCE_FILE_LINES[@]}"; do
    if [[ "${SOURCE_FILE_LINES[$i]}" == *"PROCEDURE DIVISION"* ]]; then
        PROCEDURE_DIVISION_INDEX=$i
        break
    fi
done

# ==============================================================================
# Phase 2: Analysis & Transformation
# Process the Procedure Division to inject coverage logic and build the
# report section.
# ==============================================================================

# Setup a instantiated version of the procedure division with the coverage flags instrumented
MODIFIED_PROCEDURE_DIVISION_LINES=""
# This variable will hold the section that displays the code coverage report
DISPLAY_COVERAGE_SECTION_LINES="${AREA_A_INDENT} DISPLAY-COVERAGE SECTION.\n"

# Counts how many executable verbs are found
COVERAGE_INDEX=0

# Extract the program name directly from the file using sed regex
PROGRAM_NAME=$(sed -nE 's/^.{6}[^*]PROGRAM-ID\.[[:space:]]*(.*)\..*/\1/p' "$SOURCE_FILE" | head -n 1)

# If no match is found, default to "UNKNOWN"
if [[ -z "$PROGRAM_NAME" ]]; then PROGRAM_NAME="UNKNOWN"; fi 
HEADER_1=$(cobol_wrap_display "${AREA_B_INDENT} DISPLAY \"****************************************************************************************\"" '"')
HEADER_2=$(cobol_wrap_display "${AREA_B_INDENT} DISPLAY \"    COVERAGE REPORT - $PROGRAM_NAME                                            \"" '"')
HEADER_3=$(cobol_wrap_display "${AREA_B_INDENT} DISPLAY \"****************************************************************************************\"" '"') 
DISPLAY_COVERAGE_SECTION_LINES+="$HEADER_1\n$HEADER_2\n$HEADER_3\n" 

# Define keywords that trigger a coverage check - expand as needed
EXECUTABLE_KEYWORDS="^.{6}[^*][ ]{3}[ ]*(MOVE|ADD|COMPUTE|DISPLAY|PERFORM|CALL|GOBACK|STRING|INSPECT|UNSTRING|ACCEPT|DIVIDE|MULTIPLY|SUBTRACT|SET|OPEN|CLOSE|CONTINUE)"
# Control statements that precede an exit or jump
CONTROL_KEYWORDS="STOP[[:space:]]*RUN|GO[[:space:]]*BACK"

for (( i=$PROCEDURE_DIVISION_INDEX; i<${#SOURCE_FILE_LINES[@]}; i++ )); do
    LINE="${SOURCE_FILE_LINES[$i]}"
    # Determine the appropriate quote character based on the original line content.
    # If the line contains double quotes, use single quotes for wrapping to avoid conflicts.
    # Otherwise, default to double quotes.
    q_char="\"" 
    [[ "$LINE" == *'"'* ]] && q_char="'"

    # If the line contains an executable verb or a control verb
    if [[ "$LINE" =~ ($EXECUTABLE_KEYWORDS) ]] || [[ "$LINE" =~ ($CONTROL_KEYWORDS) ]]; then
        # Advance the coverage index
        ((COVERAGE_INDEX++))

        # If the line is executable, add a flag tracker at the updated index
        MODIFIED_PROCEDURE_DIVISION_LINES+="${AREA_B_INDENT} MOVE \"1\" TO COV-FLAGS($COVERAGE_INDEX)\n"

        # If this is a control verb then run the display coverage before, otherwise the code will exit before outputing the report
        if [[ "$LINE" =~ ($CONTROL_KEYWORDS) ]]; then
            MODIFIED_PROCEDURE_DIVISION_LINES+="${AREA_B_INDENT}PERFORM DISPLAY-COVERAGE\n"                                                        
        fi
        # Add the original line back in
        MODIFIED_PROCEDURE_DIVISION_LINES+="$LINE\n"

        # Build the corresponding entry in the coverage report section
        DISPLAY_COVERAGE_SECTION_LINES+="${AREA_B_INDENT} IF COV-FLAGS($COVERAGE_INDEX) = \"1\"\n"
        DISPLAY_COVERAGE_SECTION_LINES+=$(cobol_wrap_display "${AREA_B_INDENT}     DISPLAY ${q_char}[+] $LINE${q_char}\n" "${q_char}")
        DISPLAY_COVERAGE_SECTION_LINES+="${AREA_B_INDENT} ELSE\n"
        DISPLAY_COVERAGE_SECTION_LINES+=$(cobol_wrap_display "${AREA_B_INDENT}     DISPLAY ${q_char}[-] $LINE${q_char}\n" "${q_char}")
        DISPLAY_COVERAGE_SECTION_LINES+="${AREA_B_INDENT} END-IF\n"

    else
        # If not an executable line (e.g., comment or label), just pass it through to both 
        MODIFIED_PROCEDURE_DIVISION_LINES+="$LINE\n"
        DISPLAY_COVERAGE_SECTION_LINES+=$(cobol_wrap_display "${AREA_B_INDENT}     DISPLAY ${q_char}    ${LINE}${q_char}\n" "${q_char}")
    fi
done  

# At this point the DISPLAY COVERAGE section has displays for all permutations of the procedure division
# At the end of the display coverage we need to display a summary

# Calculate statistics
DISPLAY_COVERAGE_SECTION_LINES+=${AREA_B_INDENT}"MOVE 0 TO COVERED-STMT\n"
DISPLAY_COVERAGE_SECTION_LINES+=${AREA_B_INDENT}"PERFORM VARYING COV-FLAGS-COUNTER FROM 1 BY 1 \n"
DISPLAY_COVERAGE_SECTION_LINES+=${AREA_B_INDENT}"UNTIL COV-FLAGS-COUNTER > TOTAL-STMT\n"
DISPLAY_COVERAGE_SECTION_LINES+=${AREA_B_INDENT}"    IF COV-FLAGS(COV-FLAGS-COUNTER) = \"1\"\n"
DISPLAY_COVERAGE_SECTION_LINES+=${AREA_B_INDENT}"        ADD 1 TO COVERED-STMT END-IF \n"
DISPLAY_COVERAGE_SECTION_LINES+=${AREA_B_INDENT}"END-PERFORM\n"
DISPLAY_COVERAGE_SECTION_LINES+=${AREA_B_INDENT}"COMPUTE PERCENT-CALC = \n"
DISPLAY_COVERAGE_SECTION_LINES+=${AREA_B_INDENT}"(COVERED-STMT / TOTAL-STMT) * 100\n"

# Final Summary Box
FOOTER_1=$(cobol_wrap_display "${AREA_B_INDENT} DISPLAY '****************************************************************************************'\n" "'")
FOOTER_2=$(cobol_wrap_display "${AREA_B_INDENT} DISPLAY \"    SUMMARY STATISTICS                           \"\n" '"')
FOOTER_3=$(cobol_wrap_display "${AREA_B_INDENT} DISPLAY '****************************************************************************************'\n" "'")
DISPLAY_COVERAGE_SECTION_LINES+="$FOOTER_1$FOOTER_2$FOOTER_3\n"

# Display calculated output
DISPLAY_COVERAGE_SECTION_LINES+=$(cobol_wrap_display "${AREA_B_INDENT} DISPLAY \"    TOTAL STATEMENTS: \" TOTAL-STMT\n" '"')
DISPLAY_COVERAGE_SECTION_LINES+=$(cobol_wrap_display "${AREA_B_INDENT} DISPLAY \"    COVERED STATEMENTS: \", COVERED-STMT\n" '"')
DISPLAY_COVERAGE_SECTION_LINES+=$(cobol_wrap_display "${AREA_B_INDENT} DISPLAY \"    STATEMENT COVERAGE: \", PERCENT-CALC \"%\"\n" '"')

# Final closing of the section
HEADER_2=$(cobol_wrap_display "${AREA_B_INDENT} DISPLAY \"    END OF REPORT - $PROGRAM_NAME                                            \"" '"')
DISPLAY_COVERAGE_SECTION_LINES+="$HEADER_1\n$HEADER_2\n$HEADER_3\n" 
DISPLAY_COVERAGE_SECTION_LINES+=$(cobol_wrap_display "${AREA_B_INDENT} DISPLAY \" \"\n" '"')
DISPLAY_COVERAGE_SECTION_LINES+=$(cobol_wrap_display "${AREA_B_INDENT} DISPLAY \" \"\n" '"')
DISPLAY_COVERAGE_SECTION_LINES+=$(cobol_wrap_display "${AREA_B_INDENT} DISPLAY \" \"\n" '"')
DISPLAY_COVERAGE_SECTION_LINES+=$(cobol_wrap_display "${AREA_B_INDENT} DISPLAY \" \"\n" '"')

# Add a period to cap the coverage section definition
DISPLAY_COVERAGE_SECTION_LINES+="${AREA_B_INDENT} .\n"

# Append the report section to the end of the modified procedure division
MODIFIED_PROCEDURE_DIVISION_LINES+="$DISPLAY_COVERAGE_SECTION_LINES"

# ==============================================================================
# Phase 3: Working Storage Update & Final Assembly
# Construct the final output by combining the pre-procedure part (with
# updated WORKING-STORAGE) and the modified procedure division.
# ==============================================================================
FINAL_OUTPUT=""

for (( i=0; i<$PROCEDURE_DIVISION_INDEX; i++ )); do
    LINE="${SOURCE_FILE_LINES[$i]}"
    if [[ "$LINE" == *"WORKING-STORAGE SECTION."* ]]; then
        # Replace the standard header with the one containing the dynamic count
        FINAL_OUTPUT+="${AREA_A_INDENT}WORKING-STORAGE SECTION.\n"
        FINAL_OUTPUT+="${AREA_A_INDENT} 01 COV-FLAGS OCCURS $COVERAGE_INDEX TIMES PIC 9(1) VALUE 0.\n"
        FINAL_OUTPUT+="${AREA_A_INDENT} 01 COV-STATS.\n"
        FINAL_OUTPUT+="${AREA_A_INDENT}   05 TOTAL-STMT       PIC 9(4) VALUE $COVERAGE_INDEX.\n"
        FINAL_OUTPUT+="${AREA_A_INDENT}   05 COVERED-STMT     PIC 9(4) VALUE 0.\n"
        FINAL_OUTPUT+="${AREA_A_INDENT}   05 PERCENT-CALC     PIC 9(3)V99 VALUE 0.\n"
        FINAL_OUTPUT+="${AREA_A_INDENT}   05 COV-FLAGS-COUNTER PIC 9(9) COMP VALUE 1.\n"
    else
        FINAL_OUTPUT+="$LINE\n"
    fi
done

# Append the modified procedure division (which now includes the coverage report)
FINAL_OUTPUT+="$MODIFIED_PROCEDURE_DIVISION_LINES"

# Write the final result to the output file
printf "%b" "$FINAL_OUTPUT" > "$OUTPUT_FILE"

echo "Pre-compilation complete. Output written to $OUTPUT_FILE"