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

# Widths of the raw coverage data, overridable from the environment, e.g.
#   COVERAGE_OUTPUT_WIDTH=133 code-coverage-precompiler.sh in.cbl out.cbl
# COVERAGE_OUTPUT_WIDTH - the widest *COV* line the instrumented program writes.
#   Set it to the record length of wherever the output lands, so a line is
#   never split: 80 suits an FB80 PDS member, SYSOUT is often 121/133, POSIX
#   files and VB datasets can take far more. The flags per line are derived.
# COVERAGE_INPUT_WIDTH - the widest line the combine program reads. Kept
#   separate and generous, as captured lines may gain a prefix by the system.
# lines that fill it are reported as possibly truncated.
COVERAGE_OUTPUT_WIDTH="${COVERAGE_OUTPUT_WIDTH:-80}"
COVERAGE_INPUT_WIDTH="${COVERAGE_INPUT_WIDTH:-4096}"
for setting in COVERAGE_OUTPUT_WIDTH COVERAGE_INPUT_WIDTH; do
    if [[ ! "${!setting}" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: $setting must be a positive whole number, got '${!setting}'" >&2
        exit 1
    fi
done

# Given content that may contain doubled-quote escape pairs (a literal
# occurrence of q_char, represented as q_char repeated twice), return a split
# length <= max_len that never falls between the two characters of a pair -
# doing so would close the wrapped literal one character early.
cobol_safe_split_len() {
    local content="$1"
    local len="$2"
    local q="$3"

    if (( len > ${#content} )); then
        len=${#content}
    fi

    while (( len > 0 && len < ${#content} )); do
        if [[ "${content:$((len-1)):1}" == "$q" && "${content:$len:1}" == "$q" ]]; then
            ((len--))
        else
            break
        fi
    done

    # Guard against a run of quote characters long enough to shrink the
    # split point to nothing - fall back to len 1 so the loop still progresses.
    (( len == 0 && ${#content} > 0 )) && len=1

    echo "$len"
}

# Used when trying to write long dislplay lines
cobol_wrap_display() {
    local input_line="$1"
    local q_char="$2"

    # If the line is short enough, print it as-is
    if [[ ${#input_line} -le 72 ]]; then
        echo "$input_line"
        return
    fi

    # Check if this line is a DISPLAY statement WITH QUOTES (i.e not a WS-VAR)
    # DISPLAY 'example' needs careful processing because that eventually becomes DISPLAY ' DISPLAY 'example''' <-- simplified but you get the point
    local after_open_quote="${input_line#*$q_char}"
    if [[ "$input_line" == *"DISPLAY"* ]] && [[ "$after_open_quote" == *"$q_char"* ]]; then

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
        local first_len
        first_len=$(cobol_safe_split_len "$literal_content" "$first_chunk_max" "$q_char")

        local first_chunk="${literal_content:0:$first_len}"
        local remaining="${literal_content:$first_len}"

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
                local safe_len
                safe_len=$(cobol_safe_split_len "$remaining" "$chunk_size" "$q_char")
                local chunk="${remaining:0:$safe_len}"
                printf "            %s%s%s &\n" "${q_char}" "${chunk}" "${q_char}"
                remaining="${remaining:$safe_len}"
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

# True if the line is code (column 7 is not a comment indicator) and
# contains the given text
cobol_code_line_has() {
    [[ "$1" =~ ^.{6}[^*/] ]] && [[ "$1" == *"$2"* ]]
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

# Per-program names, so instrumenting several programs side by side never collides.
# The coverage file's external name has no hyphens or quotes so that it can be
# redirected with an environment variable (e.g. DD_NOTNCROSCOV=/path/to/file),
# much like a DD statement in JCL. It defaults to a file of that name in the
# current directory.
PROGRAM_NAME_CLEAN="${PROGRAM_NAME//[^A-Za-z0-9]/}"
COVERAGE_FILE_NAME="${PROGRAM_NAME_CLEAN}COV"
COMBINE_PROGRAM_ID="${PROGRAM_NAME_CLEAN}CC"
COMBINE_OUTPUT_FILE="$(dirname "$OUTPUT_FILE")/${PROGRAM_NAME_CLEAN}-combine.cbl"
HEADER_1=$(cobol_wrap_display "${AREA_B_INDENT} DISPLAY \"****************************************************************************************\"" '"')
HEADER_2=$(cobol_wrap_display "${AREA_B_INDENT} DISPLAY \"    COVERAGE REPORT - $PROGRAM_NAME                                            \"" '"')
HEADER_3=$(cobol_wrap_display "${AREA_B_INDENT} DISPLAY \"****************************************************************************************\"" '"') 
DISPLAY_COVERAGE_SECTION_LINES+="$HEADER_1\n$HEADER_2\n$HEADER_3\n" 

# Define keywords that trigger a coverage check - expand as needed
EXECUTABLE_KEYWORDS="^.{6}[^*][ ]{3}[ ]*(MOVE|ADD|COMPUTE|DISPLAY |PERFORM|CALL|GOBACK|STRING|INSPECT|UNSTRING|ACCEPT|DIVIDE|MULTIPLY|SUBTRACT|SET|OPEN|CLOSE|CONTINUE|WRITE|GO)"
# Control statements that precede an exit or jump
CONTROL_KEYWORDS="STOP[[:space:]]*RUN|GO[[:space:]]*BACK"

for (( i=$PROCEDURE_DIVISION_INDEX; i<${#SOURCE_FILE_LINES[@]}; i++ )); do
    LINE="${SOURCE_FILE_LINES[$i]}"
    # Determine the appropriate quote character based on the original line content.
    # If the line contains double quotes, use single quotes for wrapping to avoid conflicts.
    # Otherwise, default to double quotes.
    q_char="\""
    [[ "$LINE" == *'"'* ]] && q_char="'"

    # COBOL escapes quotes by using the same quote twice
    # If the quote char is there, replace it with the same char twice
    ESCAPED_LINE="${LINE//$q_char/$q_char$q_char}"

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
        DISPLAY_COVERAGE_SECTION_LINES+=$(cobol_wrap_display "${AREA_B_INDENT}     DISPLAY ${q_char}[+] $ESCAPED_LINE${q_char}\n" "${q_char}")
        DISPLAY_COVERAGE_SECTION_LINES+="${AREA_B_INDENT} ELSE\n"
        DISPLAY_COVERAGE_SECTION_LINES+=$(cobol_wrap_display "${AREA_B_INDENT}     DISPLAY ${q_char}[-] $ESCAPED_LINE${q_char}\n" "${q_char}")
        DISPLAY_COVERAGE_SECTION_LINES+="${AREA_B_INDENT} END-IF\n"

    else
        # If not an executable line (e.g., comment or label), just pass it through to both 
        MODIFIED_PROCEDURE_DIVISION_LINES+="$LINE\n"
        DISPLAY_COVERAGE_SECTION_LINES+=$(cobol_wrap_display "${AREA_B_INDENT}     DISPLAY ${q_char}    ${ESCAPED_LINE}${q_char}\n" "${q_char}")
    fi
done  

# At this point the DISPLAY COVERAGE section has displays for all permutations of the procedure division
# At the end of the display coverage we need to display a summary

# Fingerprint the coverage mapping. Raw coverage data is only meaningful against
# the exact statement-to-flag mapping it was produced with. The report text so
# far embeds the procedure division source and marks which lines carry a flag,
# so its checksum changes whenever the source or the precompiler's choice of
# instrumented lines changes - letting the combine program reject stale data.
COVERAGE_FINGERPRINT=$(printf "%b" "$DISPLAY_COVERAGE_SECTION_LINES" | cksum | awk '{printf "%010d", $1}')

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

# Raw coverage data, for the combine program to merge across runs. Each line
# is self-contained: *COV* <fingerprint> <offset of first flag> <chunk of flags>
# Chunks are sized so every line fits COVERAGE_OUTPUT_WIDTH, so the output is
# never split, and the offset means lines can be merged in any order or
# interleaved with other output. "*" is used as the marker because it is
# invariant across EBCDIC code pages, unlike @ # $.
# UNSTRING without DELIMITED BY takes exactly as many flags as the chunk holds
# and advances the pointer by the number it actually took - so the logged
# offset always matches the data, and the last chunk is simply space-padded.
DISPLAY_COVERAGE_SECTION_LINES+="${AREA_B_INDENT} MOVE 1 TO COV-RAW-POINTER\n"
DISPLAY_COVERAGE_SECTION_LINES+="${AREA_B_INDENT} PERFORM UNTIL COV-RAW-POINTER > TOTAL-STMT\n"
DISPLAY_COVERAGE_SECTION_LINES+="${AREA_B_INDENT}     MOVE COV-RAW-POINTER TO COV-RAW-OFFSET\n"
DISPLAY_COVERAGE_SECTION_LINES+="${AREA_B_INDENT}     UNSTRING COV-FLAGS-OUTPUT INTO COV-RAW-CHUNK\n"
DISPLAY_COVERAGE_SECTION_LINES+="${AREA_B_INDENT}         WITH POINTER COV-RAW-POINTER\n"
DISPLAY_COVERAGE_SECTION_LINES+="${AREA_B_INDENT}     END-UNSTRING\n"
DISPLAY_COVERAGE_SECTION_LINES+="${AREA_B_INDENT}     DISPLAY \"*COV* \" COV-FINGERPRINT \" \" COV-RAW-OFFSET \" \"\n"
DISPLAY_COVERAGE_SECTION_LINES+="${AREA_B_INDENT}         COV-RAW-CHUNK\n"
DISPLAY_COVERAGE_SECTION_LINES+="${AREA_B_INDENT} END-PERFORM\n"

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

# Size every statement-count field from the statement count itself, so none
# can be too small to hold its values. COBOL never fails on an oversized value
# - it silently keeps the low-order digits - so sizing is the only defence.
# The widest value any of them holds is the *COV* pointer, which finishes one
# past the last flag. The combine program splits *COV* lines on spaces rather
# than reading fixed positions so it can still merge output from an earlier
# precompiler version with the same mapping fingerprint, whose offset width may
# differ - read at fixed positions, such a line could put its flags against the
# wrong statements. (Lines from other programs are rejected on their
# fingerprint, which is always the first field after the marker.)
COVERAGE_MAX_COUNT=$((COVERAGE_INDEX + 1))
COVERAGE_COUNT_DIGITS=${#COVERAGE_MAX_COUNT}

# A *COV* line is: "*COV* " + 10 digit fingerprint + " " + offset + " " + chunk
# The chunk takes whatever COVERAGE_OUTPUT_WIDTH leaves after the prefix
COVERAGE_LINE_PREFIX_WIDTH=$((6 + 10 + 1 + COVERAGE_COUNT_DIGITS + 1))
COVERAGE_CHUNK_SIZE=$((COVERAGE_OUTPUT_WIDTH - COVERAGE_LINE_PREFIX_WIDTH))
if (( COVERAGE_CHUNK_SIZE < 1 )); then
    echo "Error: COVERAGE_OUTPUT_WIDTH=$COVERAGE_OUTPUT_WIDTH leaves no room for coverage flags" \
         "- a *COV* line for $COVERAGE_INDEX statements needs at least" \
         "$((COVERAGE_LINE_PREFIX_WIDTH + 1)) columns" >&2
    exit 1
fi
# No chunk needs to be bigger than the whole flag string - DISPLAY pads the
# chunk field to its full size, so a wide setting would otherwise pad every line
if (( COVERAGE_CHUNK_SIZE > COVERAGE_INDEX )); then
    COVERAGE_CHUNK_SIZE=$COVERAGE_INDEX
fi
if (( COVERAGE_INPUT_WIDTH < COVERAGE_OUTPUT_WIDTH )); then
    echo "Error: COVERAGE_INPUT_WIDTH=$COVERAGE_INPUT_WIDTH is narrower than" \
         "COVERAGE_OUTPUT_WIDTH=$COVERAGE_OUTPUT_WIDTH - the combine program" \
         "couldn't read its own program's output" >&2
    exit 1
fi

# Positions within an input record (marker position, field lengths, flag
# index) must hold up to one past the record width - sized from it for the
# same reason as the statement counts above
COMBINE_POSITION_MAX=$((COVERAGE_INPUT_WIDTH + 1))
COMBINE_POSITION_DIGITS=${#COMBINE_POSITION_MAX}

# Working storage needed by DISPLAY-COVERAGE - shared by the instrumented
# program and the combine program, since both include that section
COVERAGE_WORKING_STORAGE=""
COVERAGE_WORKING_STORAGE+="${AREA_A_INDENT} 01 COV-FLAGS-TABLE.\n"
COVERAGE_WORKING_STORAGE+="${AREA_A_INDENT}     05 COV-FLAGS OCCURS $COVERAGE_INDEX TIMES PIC 9(1) VALUE 0.\n"
COVERAGE_WORKING_STORAGE+="${AREA_A_INDENT} 01 COV-FLAGS-ALL REDEFINES COV-FLAGS-TABLE.\n"
COVERAGE_WORKING_STORAGE+="${AREA_A_INDENT}     05 COV-FLAGS-OUTPUT PIC X($COVERAGE_INDEX).\n"
COVERAGE_WORKING_STORAGE+="${AREA_A_INDENT} 01 COV-STATS.\n"
COVERAGE_WORKING_STORAGE+="${AREA_A_INDENT}   05 TOTAL-STMT       PIC 9(${COVERAGE_COUNT_DIGITS}) VALUE $COVERAGE_INDEX.\n"
COVERAGE_WORKING_STORAGE+="${AREA_A_INDENT}   05 COVERED-STMT     PIC 9(${COVERAGE_COUNT_DIGITS}) VALUE 0.\n"
COVERAGE_WORKING_STORAGE+="${AREA_A_INDENT}   05 PERCENT-CALC     PIC 9(3)V99 VALUE 0.\n"
COVERAGE_WORKING_STORAGE+="${AREA_A_INDENT}   05 COV-FLAGS-COUNTER PIC 9(9) COMP VALUE 1.\n"
COVERAGE_WORKING_STORAGE+="${AREA_A_INDENT} 01 COV-RAW-DATA.\n"
COVERAGE_WORKING_STORAGE+="${AREA_A_INDENT}   05 COV-FINGERPRINT  PIC X(10) VALUE \"${COVERAGE_FINGERPRINT}\".\n"
COVERAGE_WORKING_STORAGE+="${AREA_A_INDENT}   05 COV-RAW-OFFSET   PIC 9(${COVERAGE_COUNT_DIGITS}).\n"
COVERAGE_WORKING_STORAGE+="${AREA_A_INDENT}   05 COV-RAW-POINTER  PIC 9(${COVERAGE_COUNT_DIGITS}).\n"
COVERAGE_WORKING_STORAGE+="${AREA_A_INDENT}   05 COV-RAW-CHUNK    PIC X(${COVERAGE_CHUNK_SIZE}).\n"

for (( i=0; i<$PROCEDURE_DIVISION_INDEX; i++ )); do
    LINE="${SOURCE_FILE_LINES[$i]}"
    if cobol_code_line_has "$LINE" "WORKING-STORAGE SECTION"; then
        # Replace the standard header with one followed by the coverage fields
        FINAL_OUTPUT+="${AREA_A_INDENT}WORKING-STORAGE SECTION.\n"
        FINAL_OUTPUT+="$COVERAGE_WORKING_STORAGE"
    else
        FINAL_OUTPUT+="$LINE\n"
    fi
done

# Append the modified procedure division (which now includes the coverage report)
FINAL_OUTPUT+="$MODIFIED_PROCEDURE_DIVISION_LINES"

# Write the final result to the output file
printf "%b" "$FINAL_OUTPUT" > "$OUTPUT_FILE"


# ==============================================================================
# Phase 4: Combine program
# Build a bespoke program that reads captured output from any number of runs
# (stdout, SYSOUT, pasted text - other lines are ignored), ORs together the
# flags from every *COV* line (a statement counts as covered if any run
# executed it) and prints the same report as the instrumented program.
# Lines whose fingerprint doesn't match this mapping are counted and skipped.
# ==============================================================================
COMBINE_COVERAGE_LINES=""
COMBINE_COVERAGE_LINES+="${AREA_A_INDENT}IDENTIFICATION DIVISION.\n"
COMBINE_COVERAGE_LINES+="${AREA_A_INDENT}PROGRAM-ID. ${COMBINE_PROGRAM_ID}.\n"
COMBINE_COVERAGE_LINES+="${AREA_A_INDENT}AUTHOR. CODE COVERAGE PRECOMPILER.\n"
COMBINE_COVERAGE_LINES+="\n"
COMBINE_COVERAGE_LINES+="${AREA_A_INDENT}ENVIRONMENT DIVISION.\n"
COMBINE_COVERAGE_LINES+="${AREA_A_INDENT}INPUT-OUTPUT SECTION.\n"
COMBINE_COVERAGE_LINES+="${AREA_A_INDENT}FILE-CONTROL.\n"
# The ASSIGN name must be a quoted literal. An unquoted, undeclared word makes
# GnuCOBOL 3.1.2 create an implicit data item whose descriptor is a reused
# temporary - later statements can overwrite it, so the file is opened under
# whatever that temporary last held (seen as a file literally named "1").
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}SELECT OPTIONAL COV-IN-FILE ASSIGN TO \"${COVERAGE_FILE_NAME}\"\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}ORGANIZATION IS LINE SEQUENTIAL\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}FILE STATUS IS COV-IN-STATUS.\n"
COMBINE_COVERAGE_LINES+="${AREA_A_INDENT}DATA DIVISION.\n"
COMBINE_COVERAGE_LINES+="${AREA_A_INDENT}FILE SECTION.\n"
COMBINE_COVERAGE_LINES+="${AREA_A_INDENT}FD COV-IN-FILE.\n"
COMBINE_COVERAGE_LINES+="${AREA_A_INDENT}01 COV-IN-REC PIC X(${COVERAGE_INPUT_WIDTH}).\n"
COMBINE_COVERAGE_LINES+="${AREA_A_INDENT}WORKING-STORAGE SECTION.\n"
COMBINE_COVERAGE_LINES+="$COVERAGE_WORKING_STORAGE"
COMBINE_COVERAGE_LINES+="${AREA_A_INDENT} 01 COV-IN-STATUS PIC XX.\n"
COMBINE_COVERAGE_LINES+="${AREA_A_INDENT} 01 COV-IN-POS PIC 9(${COMBINE_POSITION_DIGITS}) COMP.\n"
COMBINE_COVERAGE_LINES+="${AREA_A_INDENT} 01 COV-IN-INDEX PIC 9(${COMBINE_POSITION_DIGITS}) COMP.\n"
# The fields of a *COV* line, split on spaces rather than taken from fixed
# positions - so the combine accepts any offset width or chunk size, including
# output from earlier precompiler versions with the same mapping fingerprint
COMBINE_COVERAGE_LINES+="${AREA_A_INDENT} 01 COV-IN-FIELDS.\n"
COMBINE_COVERAGE_LINES+="${AREA_A_INDENT}     05 COV-IN-MARKER PIC X(5).\n"
COMBINE_COVERAGE_LINES+="${AREA_A_INDENT}     05 COV-IN-FINGERPRINT PIC X(10).\n"
COMBINE_COVERAGE_LINES+="${AREA_A_INDENT}     05 COV-IN-OFFSET PIC X(9).\n"
COMBINE_COVERAGE_LINES+="${AREA_A_INDENT}     05 COV-IN-FLAGS PIC X(${COVERAGE_INPUT_WIDTH}).\n"
COMBINE_COVERAGE_LINES+="${AREA_A_INDENT} 01 COV-IN-FINGERPRINT-LEN PIC 9(${COMBINE_POSITION_DIGITS}) COMP.\n"
COMBINE_COVERAGE_LINES+="${AREA_A_INDENT} 01 COV-IN-OFFSET-LEN PIC 9(${COMBINE_POSITION_DIGITS}) COMP.\n"
COMBINE_COVERAGE_LINES+="${AREA_A_INDENT} 01 COV-IN-OFFSET-NUM PIC 9(9).\n"
COMBINE_COVERAGE_LINES+="${AREA_A_INDENT} 01 COV-RUNS-MERGED PIC 9(9) VALUE 0.\n"
COMBINE_COVERAGE_LINES+="${AREA_A_INDENT} 01 COV-LINES-MERGED PIC 9(9) VALUE 0.\n"
COMBINE_COVERAGE_LINES+="${AREA_A_INDENT} 01 COV-LINES-SKIPPED PIC 9(9) VALUE 0.\n"
COMBINE_COVERAGE_LINES+="${AREA_A_INDENT} 01 COV-LINES-TRUNCATED PIC 9(9) VALUE 0.\n"
COMBINE_COVERAGE_LINES+="${AREA_A_INDENT} 01 END-OF-COVERAGE-FLAG PIC X VALUE 'N'.\n"
COMBINE_COVERAGE_LINES+="${AREA_A_INDENT}     88 END-OF-FILE VALUE 'Y'.\n"
COMBINE_COVERAGE_LINES+="${AREA_A_INDENT}PROCEDURE DIVISION.\n"
COMBINE_COVERAGE_LINES+="${AREA_A_INDENT}READ-COVERAGE SECTION.\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}OPEN INPUT COV-IN-FILE\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}IF COV-IN-STATUS NOT = \"00\" AND COV-IN-STATUS NOT = \"05\"\n"
COMBINE_COVERAGE_LINES+="$(cobol_wrap_display "${AREA_B_INDENT}    DISPLAY \"COVERAGE: UNABLE TO OPEN ${COVERAGE_FILE_NAME}\"" '"')\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}        \" FILE STATUS \" COV-IN-STATUS\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}    MOVE 8 TO RETURN-CODE\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}    STOP RUN\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}END-IF\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}PERFORM READ-LOOP UNTIL END-OF-FILE\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}CLOSE COV-IN-FILE\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}PERFORM DISPLAY-COVERAGE\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}DISPLAY \"    RUNS MERGED: \" COV-RUNS-MERGED\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}DISPLAY \"    COVERAGE LINES MERGED: \" COV-LINES-MERGED\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}DISPLAY \"    COVERAGE LINES SKIPPED (STALE OR MALFORMED): \"\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}    COV-LINES-SKIPPED\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}DISPLAY \"    INPUT LINES POSSIBLY TRUNCATED: \"\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}    COV-LINES-TRUNCATED\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}IF COV-LINES-TRUNCATED > 0\n"
COMBINE_COVERAGE_LINES+="$(cobol_wrap_display "${AREA_B_INDENT}    DISPLAY \"    (LINES FILLED ALL ${COVERAGE_INPUT_WIDTH} COLUMNS - RAISE COVERAGE_INPUT_WIDTH)\"" '"')\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}END-IF\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}STOP RUN\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}.\n"
COMBINE_COVERAGE_LINES+="\n"
COMBINE_COVERAGE_LINES+="${AREA_A_INDENT}READ-LOOP SECTION.\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}READ COV-IN-FILE\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}    AT END\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}        SET END-OF-FILE TO TRUE\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}    NOT AT END\n"
# A line longer than the record is silently cut off on read. A record whose
# last byte isn't a space was filled, so the line may have been longer - any
# flags it still has are correctly positioned, but some may be missing, or a
# *COV* marker may have been cut off entirely. Counted all the same, so a
# too-narrow COVERAGE_INPUT_WIDTH shows up in the report.
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}        IF COV-IN-REC(LENGTH OF COV-IN-REC:1) NOT = SPACE\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}            ADD 1 TO COV-LINES-TRUNCATED\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}        END-IF\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}        PERFORM PARSE-LINE\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}END-READ\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}.\n"
COMBINE_COVERAGE_LINES+="\n"
# Find the marker anywhere in the line - captured output may carry a prefix.
# A tally equal to the record length means the marker isn't on this line.
COMBINE_COVERAGE_LINES+="${AREA_A_INDENT}PARSE-LINE SECTION.\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}MOVE 0 TO COV-IN-POS\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}INSPECT COV-IN-REC TALLYING COV-IN-POS\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}    FOR CHARACTERS BEFORE INITIAL \"*COV* \"\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}IF COV-IN-POS < LENGTH OF COV-IN-REC\n"
# UNSTRING leaves a receiving field untouched when no data reaches it, so the
# fields are cleared first - otherwise a truncated line would inherit the
# previous line's fingerprint and offset. The offset is only valid if it is
# 1 to 9 digits; the length is checked in its own IF because COBOL doesn't
# guarantee AND stops early, and a zero-length reference modification is invalid.
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}    INITIALIZE COV-IN-FIELDS\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}    MOVE 0 TO COV-IN-FINGERPRINT-LEN COV-IN-OFFSET-LEN\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}        COV-IN-OFFSET-NUM\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}    UNSTRING COV-IN-REC(COV-IN-POS + 1:)\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}        DELIMITED BY ALL SPACE\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}        INTO COV-IN-MARKER\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}             COV-IN-FINGERPRINT\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}                 COUNT IN COV-IN-FINGERPRINT-LEN\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}             COV-IN-OFFSET\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}                 COUNT IN COV-IN-OFFSET-LEN\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}             COV-IN-FLAGS\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}    END-UNSTRING\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}    IF COV-IN-FINGERPRINT-LEN = 10\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}    AND COV-IN-FINGERPRINT = COV-FINGERPRINT\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}    AND COV-IN-OFFSET-LEN > 0\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}    AND COV-IN-OFFSET-LEN NOT > LENGTH OF COV-IN-OFFSET\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}        IF COV-IN-OFFSET(1:COV-IN-OFFSET-LEN) IS NUMERIC\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}            MOVE COV-IN-OFFSET(1:COV-IN-OFFSET-LEN)\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}                TO COV-IN-OFFSET-NUM\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}        END-IF\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}    END-IF\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}    IF COV-IN-OFFSET-NUM > 0\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}    AND COV-IN-OFFSET-NUM NOT > TOTAL-STMT\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}        ADD 1 TO COV-LINES-MERGED\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}        IF COV-IN-OFFSET-NUM = 1\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}            ADD 1 TO COV-RUNS-MERGED\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}        END-IF\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}        PERFORM OR-FLAGS\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}    ELSE\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}        ADD 1 TO COV-LINES-SKIPPED\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}    END-IF\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}END-IF\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}.\n"
COMBINE_COVERAGE_LINES+="\n"
COMBINE_COVERAGE_LINES+="${AREA_A_INDENT}OR-FLAGS SECTION.\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}MOVE COV-IN-OFFSET-NUM TO COV-FLAGS-COUNTER\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}PERFORM VARYING COV-IN-INDEX FROM 1 BY 1\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}UNTIL COV-IN-INDEX > LENGTH OF COV-IN-FLAGS\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}OR COV-FLAGS-COUNTER > TOTAL-STMT\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}    IF COV-IN-FLAGS(COV-IN-INDEX:1) = \"1\"\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}        MOVE \"1\" TO COV-FLAGS(COV-FLAGS-COUNTER)\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}    END-IF\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}    ADD 1 TO COV-FLAGS-COUNTER\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}END-PERFORM\n"
COMBINE_COVERAGE_LINES+="${AREA_B_INDENT}.\n"
COMBINE_COVERAGE_LINES+="$DISPLAY_COVERAGE_SECTION_LINES"

printf "%b" "$COMBINE_COVERAGE_LINES" > "$COMBINE_OUTPUT_FILE"

echo "Pre-compilation complete. Output written to $OUTPUT_FILE"
echo "Combine program written to $COMBINE_OUTPUT_FILE (reads captured output from ${COVERAGE_FILE_NAME})"
