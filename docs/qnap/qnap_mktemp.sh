function mktemp() {
    LOCATION=""
    PASS_OPTIONS=""
    RM_TEMPFILE=0
    while [[ $1 == -* ]]
    do
        case $1 in
        -t)
            LOCATION="${TMPDIR:-/tmp}/"
            ;;
        -u)
            RM_TEMPFILE=1
            ;;
        -d)
            PASS_OPTIONS="-d"
            ;;
        *)
            # Ignore unsupported option
            ;;
        esac
        shift
    done

    TEMPFILE=$(/bin/mktemp ${PASS_OPTIONS} ${LOCATION}$*)
    echo $TEMPFILE

    if [[ $RM_TEMPFILE -eq 1 ]]; then
        rm $TEMPFILE
    fi
}
