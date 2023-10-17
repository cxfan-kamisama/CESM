#!/bin/bash -fe

main() {

# For debugging, uncomment line below
#set -x

# --- Configuration flags ----

# Machine and project
readonly MACHINE="cheyenne"
readonly PROJECT="UMIC0075"

# Simulation
readonly COMPSET="B1850"
readonly RESOLUTION="f19_g17"
readonly CASE_NAME="CESM2.1.3_SolarFarm_${COMPSET}_${RESOLUTION}_Test"

# Code and compilation
readonly DEBUG_COMPILE=true

# Run options
readonly MODEL_START_TYPE="initial"  # 'initial', 'continue', 'branch', 'hybrid'
readonly START_DATE="0001-01-01"

# Additional options for 'branch' and 'hybrid'
readonly GET_REFCASE=TRUE
readonly RUN_REFDIR=""
readonly RUN_REFCASE=""
readonly RUN_REFDATE=""   # same as MODEL_START_DATE for 'branch', can be different for 'hybrid'

# Set paths
readonly CODE_ROOT="/glade/work/${USER}/CESM"
readonly CASE_ROOT="/glade/scratch/${USER}/CESM_UMich/${CASE_NAME}"
readonly DATA_ROOT="/glade/scratch/${USER}/inputdata"

# Sub-directories
readonly CASE_BUILD_DIR="/glade/scratch/${USER}/CESM_UMich/${CASE_NAME}/build"
readonly CASE_ARCHIVE_DIR="/glade/scratch/${USER}/CESM_UMich/${CASE_NAME}/archive"

# Define type of run
#  short tests: 'S_1x10_ndays', 'M_1x10_ndays', 'L_1x10_ndays',
#               'S_2x5_ndays', 'M_2x5_ndays', 'L_2x5_ndays',
#  or 'production' for full simulation
readonly run='L_1x10_ndays'
if [ "${run}" != "production" ]; then

  # Short test simulations
  tmp=($(echo $run | tr "_" " "))
  layout=${tmp[0]}
  units=${tmp[2]}
  resubmit=$(( ${tmp[1]%%x*} -1 ))
  length=${tmp[1]##*x}

  readonly CASE_SCRIPTS_DIR=${CASE_ROOT}/tests/${run}/case_scripts
  readonly CASE_RUN_DIR=${CASE_ROOT}/tests/${run}/run
  readonly PELAYOUT=${layout}
  readonly WALLTIME="2:00:00"
  readonly STOP_OPTION=${units}
  readonly STOP_N=${length}
  readonly REST_OPTION=${STOP_OPTION}
  readonly REST_N=${STOP_N}
  readonly RESUBMIT=${resubmit}
  readonly DO_SHORT_TERM_ARCHIVING=false

else

  # Production simulation
  readonly CASE_SCRIPTS_DIR=${CASE_ROOT}/case_scripts
  readonly CASE_RUN_DIR=${CASE_ROOT}/run
  readonly PELAYOUT="L"
  readonly WALLTIME="12:00:00"
  readonly STOP_OPTION="nyears"
  readonly STOP_N="6"
  readonly REST_OPTION="nyears"
  readonly REST_N="2"
  readonly RESUBMIT="5"
  readonly DO_SHORT_TERM_ARCHIVING=false

  # Custom pelayout
  readonly CUSTOM_PELAYOUT=false
  readonly NTASKS_ATM="-4"
  readonly NTASKS_CPL="-4"
  readonly NTASKS_OCN="-2"
  readonly NTASKS_WAV="-1"
  readonly NTASKS_GLC="-1"
  readonly NTASKS_ICE="-2"
  readonly NTASKS_ROF="-2"
  readonly NTASKS_LND="-2"

  readonly NTHRDS_ATM="1"
  readonly NTHRDS_CPL="1"
  readonly NTHRDS_OCN="1"
  readonly NTHRDS_WAV="1"
  readonly NTHRDS_GLC="1"
  readonly NTHRDS_ICE="1"
  readonly NTHRDS_ROF="1"
  readonly NTHRDS_LND="1"

  readonly ROOTPE_ATM="0"
  readonly ROOTPE_CPL="0"
  readonly ROOTPE_OCN="-4"
  readonly ROOTPE_WAV="0"
  readonly ROOTPE_GLC="0"
  readonly ROOTPE_ICE="-2"
  readonly ROOTPE_ROF="0"
  readonly ROOTPE_LND="0"
fi

# Coupler history
readonly HIST_OPTION="nyears"
readonly HIST_N="5"

# Leave empty (unless you understand what it does)
readonly OLD_EXECUTABLE=""

# --- Toggle flags for what to do ----
do_create_newcase=true
do_case_setup=true
do_case_build=true
do_case_submit=true

# --- Now, do the work ---

# Make directories created by this script world-readable
umask 022

# Create case
create_newcase

# Setup
case_setup

# Build
case_build

# Configure runtime options
runtime_options

# Copy script into case_script directory for provenance
copy_script

# Submit
case_submit

# All done
echo $'\n----- All done -----\n'

}

# =======================
# Custom user_nl settings
# =======================

user_nl() {

cat << EOF >> user_nl_cam

EOF

cat << EOF >> user_nl_clm

EOF

}

######################################################
### Most users won't need to change anything below ###
######################################################

#-----------------------------------------------------
create_newcase() {

    if [ "${do_create_newcase,,}" != "true" ]; then
        echo $'\n----- Skipping create_newcase -----\n'
        return
    fi

    echo $'\n----- Starting create_newcase -----\n'

    ${CODE_ROOT}/cime/scripts/create_newcase \
        --case ${CASE_NAME} \
        --output-root ${CASE_ROOT} \
        --script-root ${CASE_SCRIPTS_DIR} \
        --handle-preexisting-dirs u \
        --compset ${COMPSET} \
        --res ${RESOLUTION} \
        --machine ${MACHINE} \
        --project ${PROJECT} \
        --walltime ${WALLTIME} \
        --pecount ${PELAYOUT}

    if [ $? != 0 ]; then
      echo $'\nNote: if create_newcase failed because sub-directory already exists:'
      echo $'  * delete old case_script sub-directory'
      echo $'  * or set do_newcase=false\n'
      exit 35
    fi

}

#-----------------------------------------------------
case_setup() {

    if [ "${do_case_setup,,}" != "true" ]; then
        echo $'\n----- Skipping case_setup -----\n'
        return
    fi

    echo $'\n----- Starting case_setup -----\n'
    pushd ${CASE_SCRIPTS_DIR}

    # Setup some CIME directories
    ./xmlchange EXEROOT=${CASE_BUILD_DIR}
    ./xmlchange RUNDIR=${CASE_RUN_DIR}

    # Short term archiving
    ./xmlchange DOUT_S=${DO_SHORT_TERM_ARCHIVING^^}
    ./xmlchange DOUT_S_ROOT=${CASE_ARCHIVE_DIR}

    # Custom pelayout
    if [ "${CUSTOM_PELAYOUT,,}" == "true" ]; then
        ./xmlchange --file env_mach_pes.xml --id NTASKS_ATM --val ${NTASKS_ATM}
        ./xmlchange --file env_mach_pes.xml --id NTASKS_CPL --val ${NTASKS_CPL}
        ./xmlchange --file env_mach_pes.xml --id NTASKS_OCN --val ${NTASKS_OCN}
        ./xmlchange --file env_mach_pes.xml --id NTASKS_WAV --val ${NTASKS_WAV}
        ./xmlchange --file env_mach_pes.xml --id NTASKS_GLC --val ${NTASKS_GLC}
        ./xmlchange --file env_mach_pes.xml --id NTASKS_ICE --val ${NTASKS_ICE}
        ./xmlchange --file env_mach_pes.xml --id NTASKS_ROF --val ${NTASKS_ROF}
        ./xmlchange --file env_mach_pes.xml --id NTASKS_LND --val ${NTASKS_LND}

        ./xmlchange --file env_mach_pes.xml --id NTHRDS_ATM --val ${NTHRDS_ATM}
        ./xmlchange --file env_mach_pes.xml --id NTHRDS_CPL --val ${NTHRDS_CPL}
        ./xmlchange --file env_mach_pes.xml --id NTHRDS_OCN --val ${NTHRDS_OCN}
        ./xmlchange --file env_mach_pes.xml --id NTHRDS_WAV --val ${NTHRDS_WAV}
        ./xmlchange --file env_mach_pes.xml --id NTHRDS_GLC --val ${NTHRDS_GLC}
        ./xmlchange --file env_mach_pes.xml --id NTHRDS_ICE --val ${NTHRDS_ICE}
        ./xmlchange --file env_mach_pes.xml --id NTHRDS_ROF --val ${NTHRDS_ROF}
        ./xmlchange --file env_mach_pes.xml --id NTHRDS_LND --val ${NTHRDS_LND}

        ./xmlchange --file env_mach_pes.xml --id ROOTPE_ATM --val ${ROOTPE_ATM}
        ./xmlchange --file env_mach_pes.xml --id ROOTPE_CPL --val ${ROOTPE_CPL}
        ./xmlchange --file env_mach_pes.xml --id ROOTPE_OCN --val ${ROOTPE_OCN}
        ./xmlchange --file env_mach_pes.xml --id ROOTPE_WAV --val ${ROOTPE_WAV}
        ./xmlchange --file env_mach_pes.xml --id ROOTPE_GLC --val ${ROOTPE_GLC}
        ./xmlchange --file env_mach_pes.xml --id ROOTPE_ICE --val ${ROOTPE_ICE}
        ./xmlchange --file env_mach_pes.xml --id ROOTPE_ROF --val ${ROOTPE_ROF}
        ./xmlchange --file env_mach_pes.xml --id ROOTPE_LND --val ${ROOTPE_LND}
    fi

    # Turn on BFB flag
    ./xmlchange BFBFLAG=TRUE

    # Extracts input_data_dir in case it is needed for user edits to the namelist later
    if [ "${DATA_ROOT}" != "" ]; then
        mkdir -p ${DATA_ROOT}
        ./xmlchange DIN_LOC_ROOT=${DATA_ROOT}
    fi
    local input_data_dir=`./xmlquery DIN_LOC_ROOT --value`
    echo "Input Data Path: ${DATA_ROOT}"

    # Custom user_nl
    user_nl

    # Finally, run CIME case.setup
    ./case.setup --reset

    popd
}

#-----------------------------------------------------
case_build() {

    pushd ${CASE_SCRIPTS_DIR}

    # do_case_build = false
    if [ "${do_case_build,,}" != "true" ]; then

        echo $'\n----- case_build -----\n'

        if [ "${OLD_EXECUTABLE}" == "" ]; then
            # Ues previously built executable, make sure it exists
            if [ -x ${CASE_BUILD_DIR}/cesm.exe ]; then
                echo 'Skipping build because $do_case_build = '${do_case_build}
            else
                echo 'ERROR: $do_case_build = '${do_case_build}' but no executable exists for this case.'
                exit 297
            fi
        else
            # If absolute pathname exists and is executable, reuse pre-exiting executable
            if [ -x ${OLD_EXECUTABLE} ]; then
                echo 'Using $OLD_EXECUTABLE = '${OLD_EXECUTABLE}
                cp -fp ${OLD_EXECUTABLE} ${CASE_BUILD_DIR}/
            else
                echo 'ERROR: $OLD_EXECUTABLE = '$OLD_EXECUTABLE' does not exist or is not an executable file.'
                exit 297
            fi
        fi
        echo 'WARNING: Setting BUILD_COMPLETE = TRUE.  This is a little risky, but trusting the user.'
        ./xmlchange BUILD_COMPLETE=TRUE

    # do_case_build = true
    else

        echo $'\n----- Starting case_build -----\n'

        # Turn on debug compilation option if requested
        if [ "${DEBUG_COMPILE^^}" == "TRUE" ]; then
            ./xmlchange DEBUG=${DEBUG_COMPILE^^}
        fi

        # Run CIME case.build
        qcmd -- ./case.build

        # Some user_nl settings won't be updated to *_in files under the run directory
        # Call preview_namelists to make sure *_in and user_nl files are consistent.
        ./preview_namelists

    fi

    popd
}

#-----------------------------------------------------
runtime_options() {

    echo $'\n----- Starting runtime_options -----\n'
    pushd ${CASE_SCRIPTS_DIR}

    # Set simulation start date
    ./xmlchange RUN_STARTDATE=${START_DATE}

    # Segment length
    ./xmlchange STOP_OPTION=${STOP_OPTION,,},STOP_N=${STOP_N}

    # Restart frequency
    ./xmlchange REST_OPTION=${REST_OPTION,,},REST_N=${REST_N}

    # Coupler history
    ./xmlchange HIST_OPTION=${HIST_OPTION,,},HIST_N=${HIST_N}

    # Coupler budgets (always on)
    # ./xmlchange BUDGETS=TRUE

    # Set resubmissions
    if (( RESUBMIT > 0 )); then
        ./xmlchange RESUBMIT=${RESUBMIT}
    fi

    # Run type
    # Start from default of user-specified initial conditions
    if [ "${MODEL_START_TYPE,,}" == "initial" ]; then
        ./xmlchange RUN_TYPE="startup"
        ./xmlchange CONTINUE_RUN="FALSE"

    # Continue existing run
    elif [ "${MODEL_START_TYPE,,}" == "continue" ]; then
        ./xmlchange CONTINUE_RUN="TRUE"

    elif [ "${MODEL_START_TYPE,,}" == "branch" ] || [ "${MODEL_START_TYPE,,}" == "hybrid" ]; then
        ./xmlchange RUN_TYPE=${MODEL_START_TYPE,,}
        ./xmlchange GET_REFCASE=${GET_REFCASE}
	./xmlchange RUN_REFDIR=${RUN_REFDIR}
        ./xmlchange RUN_REFCASE=${RUN_REFCASE}
        ./xmlchange RUN_REFDATE=${RUN_REFDATE}
        echo 'Warning: $MODEL_START_TYPE = '${MODEL_START_TYPE}
	echo '$RUN_REFDIR = '${RUN_REFDIR}
	echo '$RUN_REFCASE = '${RUN_REFCASE}
	echo '$RUN_REFDATE = '${START_DATE}

    else
        echo 'ERROR: $MODEL_START_TYPE = '${MODEL_START_TYPE}' is unrecognized. Exiting.'
        exit 380
    fi

    popd
}

#-----------------------------------------------------
case_submit() {

    if [ "${do_case_submit,,}" != "true" ]; then
        echo $'\n----- Skipping case_submit -----\n'
        return
    fi

    echo $'\n----- Starting case_submit -----\n'
    pushd ${CASE_SCRIPTS_DIR}

    # Run CIME case.submit
    ./case.submit

    popd
}

#-----------------------------------------------------
copy_script() {

    echo $'\n----- Saving run script for provenance -----\n'

    local script_provenance_dir=${CASE_SCRIPTS_DIR}/run_script_provenance
    mkdir -p ${script_provenance_dir}
    local this_script_name=`basename $0`
    local script_provenance_name=${this_script_name}.`date +%Y%m%d-%H%M%S`
    cp -vp ${this_script_name} ${script_provenance_dir}/${script_provenance_name}

}

#-----------------------------------------------------
# Silent versions of popd and pushd
pushd() {
    command pushd "$@" > /dev/null
}
popd() {
    command popd "$@" > /dev/null
}

# Now, actually run the script
#-----------------------------------------------------
main
