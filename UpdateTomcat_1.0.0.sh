#!/bin/bash
# Tomcat Update Script
# This script updates Tomcat installations for xPlore services.
# It shuts down services, backs up existing installations, unpacks new Tomcat files, and updates the installations.
# Authored by: Austin Ross
# Date: 2024-06-10
# Version: 1.0.0

#Variables
current_tomcat_version="9.0.95"
new_tomcat_version=""
new_tomcat_file=""
tomcat_files=()
tomcat_extracted_folder=""
folder_files_exists=false
folder_backup_exists=false
server_env=""
backup_dir=""
timestamp=$(date +"%Y%m%d_%H%M%S")

path_to_xplore="/u07/xPlore/"
path_to_tomcat_directory="/u07/update/tomcat/"

tomcat_folder_cps001="CPS001_tomcat"$current_tomcat_version 
path_to_cps001=$path_to_xplore$tomcat_folder_cps001

tomcat_folder_cps002="CPS002_tomcat"$current_tomcat_version
path_to_cps002=$path_to_xplore$tomcat_folder_cps002

tomcat_folder_index_agent="Indexagent_tomcat"$current_tomcat_version
path_to_index_agent=$path_to_xplore$tomcat_folder_index_agent

tomcat_folder_primaryDsearch="PrimaryDsearch_tomcat"$current_tomcat_version
path_to_primaryDsearch=$path_to_xplore$tomcat_folder_primaryDsearch

echo "Starting Tomcat Update Script"
echo "Current Tomcat Version: $current_tomcat_version"
echo "If the current version is not $current_tomcat_version, please enter the current version now. Press Enter to accept the default."
read input_current_tomcat_version
if [ -n "$input_current_tomcat_version" ]; then
    current_tomcat_version=$input_current_tomcat_version
fi

#Prompt user for server type
echo "Press [d] if on development server, press [p] if on production server"
read server_env

# Validate server type input
while true; do
    if [ "$server_env" = "d" ] || [ "$server_env" = "p" ]; then
        break
    else
        echo "Invalid input. Please enter 'd' for development or 'p' for production."
        read server_env
    fi
done

# Prompt user for new Tomcat version
echo "Enter the new Tomcat version (e.g., 9.0.96):"
read new_tomcat_version

# Validate new Tomcat version input
while [[ ! $new_tomcat_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; do
    echo "Invalid version format. Please enter the version in the format X.Y.Z (e.g., 9.0.96):"
    read new_tomcat_version
done

# Check for required directories
echo "Searching for Tomcat Folders"

# Check for 'Files' and 'Backup' directories
if [ -d "./files" ]; then
    echo "Found Files Directory"
    folder_files_exists=true
else
    echo "Files Directory Not Found"
fi

if [ -d "./backup" ]; then
    echo "Backup Directory Found"
    folder_backup_exists=true
else
    echo "Backup Directory Not Found"
fi

# Proceed only if both directories exist

if [ "$folder_files_exists" = false ] || [ "$folder_backup_exists" = false ]; then
    echo "Required directories 'Files' and 'Backup' are missing."
    echo "Would you like to create them? (y/n)"
    read create_dirs
    if [ "$create_dirs" = "y" ]; then
        mkdir -p ./files
        mkdir -p ./backup
        echo "Directories created."
        echo "Please place the updated Tomcat files in the 'files' directory and rerun the script."
        exit 1
    else
        echo "Directories Files and Backup are required. Exiting script."   
        exit 1
    fi
fi

# Both directories exist, proceed with the script
echo "Both required directories found. Proceeding with the update."

# Function to update Tomcat
shutdown_services() {
    echo "Shutting down services..."
    
    #Shutdown CPS001
    echo "Shutting down CPS001...(1/4)"
    source $path_to_cps001/bin/stopCPS001.sh
    sleep 10
    check_shutdown "CPS001"
    
    # Shutdown CPS002
    echo "Shutting down CPS002...(2/4)"
    source $path_to_cps002/bin/stopCPS002.sh
    sleep 10
    check_shutdown "CPS002"

    # Shutdown Index Agent
    echo "Shutting down Index Agent...(3/4)"
    source $path_to_index_agent/bin/stopIndexagent.sh
    sleep 10
    check_shutdown "Indexagent"

    # Shutdown Xplore
    echo "Shutting down xPlore...(4/4)"
    source $path_to_primaryDsearch/bin/stopPrimaryDsearch.sh
    sleep 10
    check_shutdown "PrimaryDsearch"

    echo "All services shut down."
} 

check_shutdown(service_name) {
    echo "Verifying $service_name shutdown..."
    sleep 5
    if ps -ef | grep -i "$service_name" | grep -v grep > /dev/null; then
        echo "$service_name is still running. Please check manually."
        exit 1
    else
        echo "$service_name has been successfully shut down."
    fi
}

backup_existing(){
    echo "Backing up existing Tomcat installations..."

    
    $backup_dir="./backup/tomcat_backup_$timestamp"
    mkdir -p $backup_dir

    echo "Backing up CPS001 Tomcat..."
    mkdir -p $backup_dir/CPS001/
    cp -r $path_to_cps001 $backup_dir/CPS001/

    echo "Backing up CPS002 Tomcat..."
    mkdir -p $backup_dir/CPS002/
    cp -r $path_to_cps002 $backup_dir/CPS002/

    echo "Backing up Index Agent Tomcat..."
    mkdir -p $backup_dir/Indexagent/
    cp -r $path_to_index_agent $backup_dir/Indexagent/

    echo "Backing up PrimaryDsearch Tomcat..."
    mkdir -p $backup_dir/PrimaryDsearch/
    cp -r $path_to_primaryDsearch $backup_dir/PrimaryDsearch/

    echo "Compressing backup folders..."
    tar -czf $backup_dir/tomcat_backup_$timestamp.tar.gz -C ./backup tomcat_backup_$timestamp

    echo "Cleaning up uncompressed backup folders..."
    rm -rf $backup_dir/CPS001/ $backup_dir/CPS002/ $backup_dir/Indexagent/ $backup_dir/PrimaryDsearch/
    
    echo "Backup completed. Backup stored in $backup_dir"
}

get_tomcat_files() {
    echo "Searching for Tomcat compressed files in 'files' directory..."

    # Search for any Tomcat compressed file (zip, tar.gz, tgz, tar) in the 'files' directory

    $tomcat_files=($(ls ./files/ | grep -E "tomcat.*\.(zip|tar\.gz|tgz|tar)$"))
    if [ ${#tomcat_files[@]} -eq 0 ]; then
        echo "No Tomcat compressed file found in 'files' directory. Please add the file and rerun the script."
        exit 1
    fi

    echo "Found the following Tomcat compressed files:"
    for i in "${!tomcat_files[@]}"; do
        echo "[$((i+1))] ${tomcat_files[$i]}"
    done

    echo "Enter the number of the file you want to use:"
    read file_choice

    while ! [[ "$file_choice" =~ ^[1-9][0-9]*$ ]] || [ "$file_choice" -lt 1 ] || [ "$file_choice" -gt "${#tomcat_files[@]}" ]; do
        echo "Invalid selection. Please enter a valid number:"
        read file_choice
    done

    $new_tomcat_file="${tomcat_files[$((file_choice-1))]}"

    if [ -z "$new_tomcat_file" ]; then
        echo "No Tomcat compressed file found in 'files' directory. Please add the file and rerun the script."
        exit 1
    else
        echo "Found Tomcat compressed file: $new_tomcat_file"
    fi
}

update_tomcat_location() {

    case $1 in
        "CPS001")
            tomcat_path=$path_to_cps001
            ;;
        "CPS002")
            tomcat_path=$path_to_cps002
            ;;
        "Indexagent")
            tomcat_path=$path_to_index_agent
            ;;
        "PrimaryDsearch")
            tomcat_path=$path_to_primaryDsearch
            ;;
        *)
            echo "Unknown service: $1"
            return
            ;;
    esac

    echo "Removing old Tomcat files from $tomcat_path..."
    rm -rf $tomcat_path/*

    echo "Copying new Tomcat files to $tomcat_path..."
    cp -r ./working/$tomcat_extracted_folder/* $tomcat_path/

    echo "Tomcat location for $1 updated successfully."
}

update_tomcat() {
    
    echo "Checks completed. Proceeding with Tomcat update..."

    # Step 1: Shutdown Services
    shutdown_services

    # Step 2: Get Tomcat Files
    get_tomcat_files
    echo "Using Tomcat file: $new_tomcat_file"

    # Step 3: Unpack Tomcat
    echo "Unpacking Tomcat..."

    # Creating Backup of Existing Tomcat Installations
    backup_existing

    echo "Creating Working Folder..."
    mkdir ./working

    echo "Unpacking Tomcat (.zip, .tar.gz, .tgz, .tar) to Working Folder..."
    # If a zip file is found, unpack using zip
    if [[ $new_tomcat_file == *.zip ]]; then
        unzip $new_tomcat_file -d ./working/

    # If a tar.gz or tgz file is found, unpack using tar
    elif [[ $new_tomcat_file == *.tar.gz ]] || [[ $new_tomcat_file == *.tgz ]]; then
        tar -xzf $new_tomcat_file -C ./working/
    
    # If a tar file is found, unpack using tar
    elif [[ $new_tomcat_file == *.tar ]]; then
        tar -xf $new_tomcat_file -C ./working/
    else
        echo "No valid Tomcat compressed file found. Exiting."
        exit 1
    fi
    echo "Tomcat unpacked successfully."

    $tomcat_extracted_folder=$(ls ./working/ | grep "tomcat")
    echo "Extracted Tomcat Folder: $tomcat_extracted_folder"

    # Step 4: Update CPS001 Tomcat
    echo "Updating CPS001 Tomcat..."
    update_tomcat_location "CPS001"

    # Step 5: Update CPS002 Tomcat
    echo "Updating CPS002 Tomcat..."
    update_tomcat_location "CPS002"

    # Step 6: Update Index Agent Tomcat
    echo "Updating Index Agent Tomcat..."
    update_tomcat_location "Indexagent"

    # Step 7: Update PrimaryDsearch Tomcat
    echo "Updating PrimaryDsearch Tomcat..."
    update_tomcat_location "PrimaryDsearch"

    # Step 8: Cleanup Working Directory
    echo "Cleaning up working directory..."
    rm -rf ./working

    echo "Tomcat update completed successfully."
    echo "Press [Enter] to exit."
    read exit_input

        
}

