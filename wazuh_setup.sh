#!/bin/bash

# Function to display welcome message
welcome_message() {
  echo "#############################################"
  echo "##   Welcome to the setup of Wazuh HIDS.   ##"
  echo "#############################################"
}

# Function to check for interrupted dpkg process
check_interrupted_dpkg() {
  if [ -f /var/lib/dpkg/lock ]; then
    echo "Error: dpkg process is interrupted. Running 'dpkg --configure -a' to correct the problem."
    dpkg --configure -a
  fi
}

# Function to check for existing Wazuh installations
check_existing_wazuh() {
  local existing_wazuh=false
  if systemctl is-active --quiet wazuh-manager; then
    existing_wazuh=true
  fi
  echo "$existing_wazuh"
}

# Function to remove existing Wazuh installations
remove_existing_wazuh() {
  echo "#############################################"
  echo "##  Removing existing Wazuh installations  ##"
  echo "#############################################"
  systemctl stop wazuh-manager
  apt-get purge wazuh-manager -y
  rm -rf /etc/wazuh /var/ossec
  rm -f /etc/apt/sources.list.d/wazuh.list
  echo "Existing Wazuh installations removed successfully."
}

# Function to integrate Wazuh HIDS with Filebeat
integrate_wazuh() {
  echo "#############################################"
  echo "##   Integrating Wazuh HIDS with Filebeat  ##"
  echo "#############################################"

  # Check for interrupted dpkg process
  check_interrupted_dpkg

  # Remove existing Wazuh Kibana plugin
  remove_existing_kibana_plugin

  # Install the GPG key
  curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import && chmod 644 /usr/share/keyrings/wazuh.gpg

  # Add the repository
  echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" | tee -a /etc/apt/sources.list.d/wazuh.list

  # Update package information
  apt-get update

  # Install the Wazuh manager package
  apt-get install wazuh-manager -y

  # Enable and start the Wazuh manager service
  systemctl daemon-reload
  systemctl enable wazuh-manager
  systemctl start wazuh-manager

  # Check if the Wazuh manager is active
  echo "Checking the status of Wazuh manager..."
  
  # Check if the Wazuh manager is active without displaying the status
if systemctl is-active --quiet wazuh-manager; then
  echo "Wazuh manager is active and running."
else
  echo "Wazuh manager is not running."
fi

  # Configure Filebeat for Wazuh
  cat <<EOF >> /etc/filebeat/filebeat.yml
filebeat.modules:
  - module: wazuh
    alerts:
      enabled: true
    archives:
      enabled: false

setup.template.json.enabled: true
setup.template.json.path: /etc/filebeat/wazuh-template.json
setup.template.json.name: wazuh
setup.template.overwrite: true
setup.ilm.enabled: false

logging.metrics.enabled: false

seccomp:
  default_action: allow
  syscalls:
  - action: allow
    names:
    - rseq
EOF

  # Download the alerts template for Elasticsearch
  curl -so /etc/filebeat/wazuh-template.json https://raw.githubusercontent.com/wazuh/wazuh/4.5/extensions/elasticsearch/7.x/wazuh-template.json
  chmod go+r /etc/filebeat/wazuh-template.json

  # Download the Wazuh module for Filebeat
  curl -s https://packages.wazuh.com/4.x/filebeat/wazuh-filebeat-0.2.tar.gz | tar -xvz -C /usr/share/filebeat/module

  # Restart the Filebeat service
  systemctl daemon-reload
  systemctl restart filebeat

  # Create the /usr/share/kibana/data directory
  mkdir /usr/share/kibana/data
  chown -R kibana:kibana /usr/share/kibana

  # Install the Wazuh Kibana plugin
  cd /usr/share/kibana
  sudo -u kibana /usr/share/kibana/bin/kibana-plugin install https://packages.wazuh.com/4.x/ui/kibana/wazuh_kibana-4.5.3_7.17.13-1.zip

  # Restart the Kibana service
  systemctl daemon-reload
  systemctl restart kibana

  echo "Wazuh HIDS integration completed successfully."
}

# Function to remove existing Wazuh Kibana plugin
remove_existing_kibana_plugin() {
  local kibana_plugin_path="/usr/share/kibana/plugins/wazuh"

  if [ -d "$kibana_plugin_path" ]; then
    echo "Removing existing Wazuh Kibana plugin..."
    rm -rf "$kibana_plugin_path"
    echo "Existing Wazuh Kibana plugin removed successfully."
  fi
}

# Main script execution
welcome_message

# Check for existing Wazuh installations
existing_wazuh=$(check_existing_wazuh)

if [ "$existing_wazuh" = true ]; then
  read -p "Existing Wazuh installation found. Do you want to remove it? (y/n): " remove_existing
  if [ "$remove_existing" = "y" ]; then
    remove_existing_wazuh
  else
    echo "Exiting script. Please remove the existing Wazuh installation manually or rerun the script."
    exit 1
  fi
fi

# Integrate Wazuh HIDS with Filebeat
integrate_wazuh

# Wait for Kibana to be up and running (adjust sleep time as needed)
sleep 60  # Increase sleep time to 60 seconds (1 minute)

# Run filebeat setup -e
filebeat setup -e

# Check the exit status of the previous command
if [ $? -eq 0 ]; then
  echo "Filebeat setup completed successfully."
else
  echo "Error: Filebeat setup failed."
fi

