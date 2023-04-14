#!/bin/bash

# This script upgrades Anthos clusters on bare metal.

# Proceed check confirmation function

proceed_check() {
    while true; do
        read -p "Do you want to proceed (yes/no)? " answer
        case $answer in 
        [Yy]* ) break;;
        [Nn]* ) exit;;
        * ) echo "Please answer yes or no"
        esac
    done
}

# Print the Maintenance WindoW

read -p "Get total node count (yes/no)? " answer

NODES_COUNT=$(kubectl get no --no-headers | wc -l)
MAINTENANCE_WINDOW_MINUTES=$((10*$NODES_COUNT))

echo "Estimated maintenance window duration : $MAINTENANCE_WINDOW_MINUTES minutes for $NODES_COUNT Node(s)"

proceed_check

# Check the version of Anthos clusters on bare metal.

# VERSION=$(bmctl get cluster version)
VERSION="1.13.0"
# Check the version of Anthos clusters on bare metal that you want to upgrade to.

TARGET_VERSION="1.14.0"

# Check if the current version of Anthos clusters on bare metal is the same as the version that you want to upgrade to.

if [[ $VERSION == $TARGET_VERSION ]]; then

echo "The current version of Anthos clusters on bare metal is the same as the version that you want to upgrade to. No upgrade is necessary."

exit 0

fi
proceed_check

# Check compatability of the other Anthos Components such as Anthos service mesh and config management.
echo "https://cloud.google.com/anthos/docs/version-and-upgrade-support#anthos-on-premises"

proceed_check

# Check Cluster resource utilization 

echo "Checking cluster resource utilization"
kubectl top nodes

proceed_check

# Check Admin cluster control plane resources requirements

# Set requirements for each scenario
admin_cluster_req_cpu=1000
admin_cluster_req_ram=3
hybrid_cluster_req_cpu=1000
hybrid_cluster_req_ram=3
standalone_req_cpu=200
standalone_req_ram=1

# Get resource usage information for the specified namespace (e.g., kube-system)
NAMESPACE="kube-system"
resource_usage=$(kubectl top pods -n $NAMESPACE --no-headers)

# Calculate total CPU and memory usage in the namespace
total_cpu=0
total_ram=0

while read -r line; do
  cpu=$(echo $line | awk '{print $2}')
  ram=$(echo $line | awk '{print $3}' | sed 's/Mi//')

  total_cpu=$((total_cpu + cpu))
  total_ram=$((total_ram + ram))
done <<< "$resource_usage"

total_ram_gib=$(echo "scale=2; $total_ram / 1024" | bc)

echo "Total CPU (mCPU): $total_cpu"
echo "Total RAM (GiB): $total_ram_gib"

# Verify requirements
if [[ $total_cpu -ge $admin_cluster_req_cpu ]] && [[ $(echo "$total_ram_gib >= $admin_cluster_req_ram" | bc -l) -eq 1 ]]; then
  echo "Admin cluster upgrade (with user cluster) requirements are met."
else
  echo "Admin cluster upgrade (with user cluster) requirements are not met."
fi

if [[ $total_cpu -ge $hybrid_cluster_req_cpu ]] && [[ $(echo "$total_ram_gib >= $hybrid_cluster_req_ram" | bc -l) -eq 1 ]]; then
  echo "Hybrid cluster upgrade (without user cluster) requirements are met."
else
  echo "Hybrid cluster upgrade (without user cluster) requirements are not met."
fi

if [[ $total_cpu -ge $standalone_req_cpu ]] && [[ $(echo "$total_ram_gib >= $standalone_req_ram" | bc -l) -eq 1 ]]; then
  echo "Standalone requirements are met."
else
  echo "Standalone requirements are not met."
fi


# Check if the cluster is healthy.

if bmctl check cluster | grep -q "Healthy"; then

echo "The cluster is healthy. Proceeding with upgrade."

else

echo "The cluster is not healthy. Please fix the issues before proceeding with upgrade."

exit 1

fi

# Warn Workload draining

echo "Following deployments have just one or less riplicas"
kubectl get deployments -A -o jsonpath='{range .items[?(@.spec.replicas<=1)]}{.metadata.name}{"\t"}{.spec.replicas}{"\n"}{end}'

proceed_check

# Check SELinux status on RHEL and CentOS

if [-f /etc/redhad-release]; then
echo "Checking SELinux status"
getenforce
fi

# Back up the cluster.
echo "Backup cluster"

bmctl backup cluster  -c "cluster-name" -f /tmp/cluster-backup.tar.gz

# Upgrade the cluster.
echo "Upgrade cluster"
proceed_check
bmctl upgrade cluster -c "cluster-name" --version $TARGET_VERSION

# Verify that the cluster is upgraded successfully.

echo "Verify that the cluster is upgraded successfully"
proceed_check

if bmctl check cluster  --cluster=cluster-name | grep -q "Healthy"; then

echo "The cluster is upgraded successfully."

else

echo "The cluster is not upgraded successfully. Please fix the issues before proceeding."

exit 1

fi

# Remove the backup.
echo "Remove the backup"
rm -rf /tmp/cluster-backup.tar.gz
