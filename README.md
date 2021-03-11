# Overview

This project provides scripts to create an OpenShift cluster,
to deploy OpenShift Container Storage on that cluster, and to enable the
project ocs-ci for testing purposes on Power Servers.  Environment variables
are used to specify parameters such as the OpenShift Version, the OpenShift
Container Storage Version, and the number and size of worker nodes.

This project creates an OpenShift Cluster running in

- libvirt/KVM based VMs on a single RHEL 8 ppc64le server
- PowerVS based LPARs in IBM Cloud

## User Setup

This project is intended to be run **unattended**, so that it may be used in
automated test frameworks like **Jenkins** and **cron**.  This project may
be run by non-root users with *passwordless sudo* authority, so that scripts
don't prompt for the root password when installing packages and performing
other privileged operations.  A helper script is provided for this purpose at
**scripts/helper/set-passwordless-sudo.sh**.  There are no command arguments
for this script and it should be run once during initial setup which includes
cloning this project and placing a few files as described below.

*Note: When debugging or monitoring, non-root users must use
the **sudo** command with **virsh** to see VMs*

## Scripts

The scripts below correspond to high level tasks of OCS-CI.  They are intended to
be invoked from an automation test framework such as *Jenkins*.
The scripts are listed in the order that they are expected to be run.

- create-ocp.sh [ --retry ]
- setup-ocs-ci.sh
- deploy-ocs-ci.sh
- add-data-disk-workers.sh
- test-ocs-ci.sh [ --tier <0,1,...> ]
- teardown-ocs-ci.sh
- destroy-ocp.sh

This project uses the following git submodules:

- github.com/ocp-power-automation/ocp4-upi-kvm 
- github.com/ocp-power-automation/ocp4-upi-powervs
- github.com/red-hat-storage/ocs-ci

These submodules must be instantiated before the create, setup, deploy, and test 
scripts may be used. 
[Workflow sample scripts](https://github.com/lukebrowning/ocs-upi-kvm#workflow-sample-scripts)
are provided to simplify the end to end operation from git submodules to cluster creation through ocs-ci testing
so that users don't have to manage these tasks individually.  These sample scripts may be copied to the
[workspace directory](https://github.com/lukebrowning/ocs-upi-kvm#workspace-directory)
and edited to customize a work flow.  Most users are expected to use the sample scripts.

Ignoring sample scripts, there are two ways to git clone projects with submodules:
```
git clone https://github.com/ocp-power-automation/ocs-upi-kvm --recursive
cd ocs-upi-kvm/scripts
```
*OR*
```
git clone https://github.com/ocp-power-automation/ocs-upi-kvm.sh
cd ocs-upi-kvm
git submodule update --init
```
The information provided below describes some of the dynamics
surrounding the create, deploy, and test scripts.

The majority of the **create-ocp.sh** command is spent running terraform (and ansible).
On occasion, a transient error will occur while creating the cluster.  In this case,
the operation can be restarted by specifying the  **--retry** argument.  This can save
half an hour of execution time.  If this argument is not specified, the existing
cluster will be torn down automatically assuming there is one.

If a failure occurs while running the **deploy-ocs-ci.sh** script, the operation has to be
restarted from the beginning.  That is to say with **creat-ocp.sh**.  Do not specify
the --retry argument as the OCP cluster has to be completely removed before trying to deploy
OCS.  The ocs-ci project alters the state of the OCP cluster.

Further, the **teardown-ocs-ci.sh** script has never been obcserved to work cleanly.  This
simply invokes the underlying ocs-ci function.  It is provided as it may be fixed in time
and it is a valuable function, if only in theory now.

The script **destroy-ocp.sh** completely removes the OCP cluster and OCS (with it as
OCS is built on top of the cluster).  For OCP KVM clusters, the cluster is completely
and reliably removed via virsh and bash commands.  For OCP PowerVS cluster, this
operation is not fully reliable.  Terraform destroy is used and it fails about 50% of
the time, so manual cleanup may be required.  Use the IBM Cloud GUI in this case.

The script **create-ocp.sh** will also remove an existing OCP cluster if one is present
before creating a new one as *only one OCP cluster is supported on the host KVM server
at a time*.  This is true even if the cluster was created by another user, so if you are
concerned with impacting other users run this command first, *sudo virsh list --all*.

The script **add-data-disk-workers.sh** may be used to add a data disk
to each KVM based worker node based on the value of the environment variable VDISK
which by default is initialized to vdd.  The first data disk is added
by the script **create-ocp.sh** at /dev/vdc, so the environment variable
VDISK does not need to be set by the user for the second data disk,
but it does for the third, fourth, ...  Please note this is a disruptive
operation, each worker node is rebooted once to make the disk visible
inside the VM, and possibly a second time to recover ceph services.  You
may have to wait 10 minutes after this script completes to identify
the extra disk with the command 'oc get pv'.

**Notes**:

- If you **Ctrl-C** while **create-ocp.sh** is running on **powervs**, then
you will need to manually remove cluster resources using the IBM Cloud GUI.
These resources are orphaned and will not be automatically removed when the
next cluster is created from the same **$WORKSPACE** directory.

- The add disk capability is not integrated into OCS-CI tests

## Workflow Sample Scripts

```
samples/dev-ocs.sh [--retry-ocp] [--latest-ocs] 
samples/test-ocs.sh [--retry-ocp] [--latest-ocs]
```

These scripts are useful in getting started.  They implement the full sequence of
high level tasks defined above.  The **test-ocs.sh** invokes **ocs-ci** tier tests
2, 3, 4, 4a, 4b, and 4c.  Both scripts designate the use of file backed Ceph disks
which are based on qcow2 files.  These files are sparsely populated enabling the 
use of servers with as little as 256 GBs of storage, depending on the number of 
worker nodes that are requested.  The use of file backed data disks is the default.
The test-ocs scripts include comments showing how physical disk partitions may
be used instead which may improve performance and resilience.

As noted above, these scripts may be relocated, customized, and invoked from the
[workspace directory](https://github.com/lukebrowning/ocs-upi-kvm#workspace-directory)

## Workspace Directory

This project is designed to be used in an automated test framework like Jenkins which utilizes
dedicated workspaces to run jobs in parallel on the same server.  As such, all input, output,
and internally generated files are restricted to the specific workspace instance that
is allocated to run the job.  For this project, that workspace is assumed to be 
the **parent** directory of the cloned project **ocs-upi-kvm** itself.

**IMPORTANT NOTE**: Do not set the WORKSPACE environment variable unless you know what you are
doing.  The only tested configuration is as stated -- the parent directory of ocs-upi-kvm.
Terraform and GO modules are built in the workspace directory.  We encountered an incompatibility
with another project that uses terraform.  If you encounter a terraform module missing problem,
see this [section](https://github.com/lukebrowning/ocs-upi-kvm#terraform-module-issues).

## Required Files

These files should be placed in the workspace directory.

- $WORKSPACE/auth.yaml
- $WORKSPACE/pull-secret.txt
- $WORKSPACE/$BASTION_IMAGE (KVM only)

The auth.yaml file is required for the script deploy-ocs-ci.sh.  It contains secrets
for **quay** and **quay.io/rhceph-dev** which are obtained from the Redhat OCS-CI team.

The pull-secret.txt is required for the scripts create-ocp.sh and deploy-ocs-ci.sh.
Download your managed pull secrets from https://cloud.redhat.com/openshift/install/pull-secret and add
the secret for **quay.io/rhceph-dev** noted above to the pull-secret.txt file.  You will
also need to add the secret for **registry.svc.ci.openshift.org** which may be obtained as follows:

1.  Become a member of [openshift organization](https://github.com/openshift)
2.  login to https://api.ci.openshift.org/console/catalog
3.  Click on "copy login command" under username in the right corner. (This will copy the oc login command to your clipboard.)
4.  Now open your terminal, paste from the clipboard buffer and execute that command you just pasted (oc login).
5.  Execute the oc registry login --registry registry.svc.ci.openshift.org which will store your token in ~/.docker/config.json.

The bastion image is a prepared image downloaded from the Red Hat Customer Portal following these
[instructions](https://github.com/ocp-power-automation/ocp4-upi-kvm/blob/master/docs/automation_host_prereqs.md).
It is named by the environment variable BASTION_IMAGE which has a default
value of "rhel-8.2-update-2-ppc64le-kvm.qcow2".  This is the name of the file downloaded
from the RedHat website.

When preparing the bastion image above, the root password must be set to **123456**.

## Environment Variables

Most users will only need to specify four or five variables below, because
platform specific default values are set that are suitable for most deployments.
Default settings are in general static.  For example, CPU and memory settings are not
dynamically scaled based on the number of OCP worker nodes.
All settings may be overridden by the user.

Variable | Required | Platform | Values (default first)
-------- | -------- | -------- | ----------------------
RHID_USERNAME | yes | all | User provided option 1
RHID_PASSWORD | yes | all | User provided option 1
RHID_ORG | yes | all | User provided option 2
RHID_KEY | yes | all | User provided option 2
OCP_VERSION | no | all | 4.6, 4.4, 4.5, 4.7, 4.8
OCS_VERSION | no | all | 4.6, 4.7
OCS_REGISTRY_IMAGE | no | all | Depends on OCS_VERSION
PLATFORM | no | all | kvm, powervs
WORKERS | no | all | 3
MASTER_DESIRED_CPU | no	| all | Depends on platform
MASTER_DESIRED_MEM | no | all | Depends on platform
WORKER_DESIRED_CPU | no	| all | Depends on platform
WORKER_DESIRED_MEM | no	| all |	Depends on platform
DNS_BACKUP_SERVER | no | all | Specify if behind a firewall
CHRONY_CONFIG | no | all | yes
CHRONY_CONFIG_SERVERS | no | all | See code for example ntp servers
BASTION_IMAGE | yes | kvm | rhel-8.2-update-2-ppc64le-kvm.qcow2
IMAGES_PATH | no | kvm | /var/lib/libvirt/images, /home/libvirt/images
DATA_SIZE | no | kvm | 256 Limited by filesystem space
DATA_DISK_LIST | no | kvm | Disk partitions: sdc1,sdd1,sde1
FORCE_DISK_PARTITION_WIPE | no | kvm | false
PVS_API_KEY | yes | powervs | User provided
PVS_SERVICE_INSTANCE_ID | yes | powervs | User provided
PVS_REGION | no | powervs | lon, tok Depends on service instance
PVS_ZONE | no | powervs | lon06, tok06 Depends on service instance
PVS_SUBNET_NAME | no | powervs | ocp-net
SYSTEM_TYPE | no | powervs | s922, e980
PROCESSOR_TYPE | no | powervs | shared, dedicated
BASTION_IMAGE | no | powervs | Depends on OCP version and cloud zone
RHCOS_IMAGE | no | powervs | Depends on OCP version and cloud zone 
DNS_FORWARDERS | no | powervs |	1.1.1.1;9.9.9.9
CLUSTER_ID_PREFIX | no | powervs | First 6 RHID_USERNAME + OCP_VERSION
CLUSTER_DOMAIN | no | powervs | ibm.com, xip.io
VOLUME_TYPE | no | powervs | tier3, ssd, standard, tier1
WORKER_VOLUME_SIZE | no | powervs | 500

Note: 

- OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE is not shown above.  It applies  
to all platforms and is optional.  Too big for the table.  See desc below.

## Environment Variables For All OCP Clusters

Specify either **RHID_USERNAME / RHID_PASSWORD** or **RHID_ORG / RHID_KEY**.

The OpenShift installer uses the latest available image which by default is
a development build.  For released OCP versions, this tool will chose a recently
released image based on the environment OCP_VERSION.  This image may not be
latest available version.  This internal selection may be overriden by setting
the environment variable **OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE**
to a [development preview image](https://mirror.openshift.com/pub/openshift-v4/ppc64le/clients/ocp-dev-preview/).

Set a specific daily build like this:
```
REGISTRY="registry.svc.ci.openshift.org/ocp-ppc64le/release-ppc64le"
export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="$REGISTRY:4.6.0-0.nightly-ppc64le-2020-09-27-075246"
```

The **RHCOS_RELEASE** parameter is specific to the **OCP_VERSION** and is set internally
to the [latest available *rhcos* image available](https://mirror.openshift.com/pub/openshift-v4/ppc64le/dependencies/rhcos/)
provided that it is not set by the user.  The internal setting may be outdated.

The **OCS_VERSION** variable identifies the version of OCS to be installed.  By default, the
image with the tag *latest-$OCS_VERSION* is pulled from https://quay.io/repository/rhceph-dev/ocs-registry/.
You may specify an alternative catalog source and image by setting the environment variable **OCS_REGISTRY_IMAGE**.

The **CHRONY_CONFIG** parameter above enables NTP servers as OCS CI expects them
to be configured.  If that is not applicable, then this parameter should probably
be set to false.

The **DNS_BACKUP_SERVER** parameter names a secondary DNS server.  The default
value should be overridden if the cluster to be deployed is behind a firewall.

## Environment Variables For OCP Clusters on libvirt/KVM

The script **create-ocp.sh** will add a data disk to each worker node.
This disk is presented inside the worker node as /dev/vdc.  In the KVM host server OS,
the data disk is backed by either a file or a physical disk partition.  If you specify
the environment variable DATA_DISK_LIST, then the named physical disk partitions (/dev) will be used.
The list is composed of comma separated unique partition names with one partition name
specified per worker node. For example,
```
export DATA_DISK_LIST="sdi1,sdi2,sdi3"
```
Otherwise, the data disks will be backed by a file.  The environment variable
DATA_DISK_SIZE controls the size of the file allocation.  If you don't want the
extra disk to be allocated, then set DATA_DISK_SIZE=0.  In this case, don't run
the scripts **setup-ocs-ci.sh** or **deploy-ocs-ci.sh** as they will fail.

The environment variable FORCE_DISK_PARTITION_WIPE may be set to 'true' to wipe
the data on a hard disk partition assuming the environment variable DATA_DISK_LIST is
specified.  The wipe may take an hour or more to complete.

## Environment Variables For OCP Clusters on PowerVS

Login to the [IBM CLoud Shell](https://cloud.ibm.com/shell) and enter the command below:

```
LukeBrowning@cloudshell:~$ ibmcloud pi service-list
Listing services under account IBM - Power Cloud as user LukeBrowning@us.ibm.com...
ID                                                                                Name
crn:v1:bluemix:public:power-iaas:<zone>:a/65bbfbd893c2c:<service instance id>::   ocp-ocs-london-06
```

The parameters **PVS_ZONE** and **PVS_SERVICE_INSTANCE_ID** are derived from the ibmcloud command.

Presumably, the **PVS_REGION** parameter is the first three characters of the **PVS_ZONE**.

Use [IBM Cloud Identity & Access Management](https://cloud.ibm.com/iam/apikeys) to create
and download the parameter **PVS_API_KEY**.

## Pre OCP Cluster Creation

*The haproxy discussion below only applies to KVM based clusters.*

Beyond placing required files, setting environment variables, and invoking scripts, you
may need to modify the number of worker nodes that are listed in the ***HAProxy** config file*
located at *ocs-upi-kvm/files/kvm/haproxy.cfg*.

By default, this file includes IP Addresses for 10 worker nodes.  If you are creating a
cluster with more worker nodes, then you should edit this file within the project to accomodate
the extra worker nodes as this file is copied to the target location by this toolset
potentially multiple times depending on how long lived the cloned instance of the project is.

The first time that the *create cluster* script is run the host server is installed and
configured to run virtual machines.  Subsequently, the host may be reconfigured as fixes
and new capabilities are delivered.  It is fairly rare for the host to be reconfigured
but it does happen.  The last time this occurred when RHEL 8.3 was released.

Editing the local copy of the HAProxy config file within this project ensures that your desired
changes are always applied.  You do not need to edit this file if you are creating less than
6 worker nodes.

## Post OCP Cluster Creation

Build artifacts are placed in the *workspace* directory which is defined as the
parent directory of this github project **ocs-upi-kvm**.  The examples shown below
use a dedicated directory for this purpose as there are quite a few output
files, some of which are not shown below such as rpms and tar files that are
downloaded during cluster creation.

### The **oc** Command

Upon successful completion of the **create-ocp.sh** script, the **oc** command
may be invoked in the following way:
```
[user@kvm-host workspace]$ source env-ocp.sh
[user@kvm-host workspace]$ oc get nodes
NAME       STATUS   ROLES    AGE   VERSION
master-0   Ready    master   40h   v1.19.0+d59ce34
master-1   Ready    master   40h   v1.19.0+d59ce34
master-2   Ready    master   40h   v1.19.0+d59ce34
worker-0   Ready    worker   39h   v1.19.0+d59ce34
worker-1   Ready    worker   39h   v1.19.0+d59ce34
worker-2   Ready    worker   39h   v1.19.0+d59ce34
```
The **env-ocp.sh** script exports **KUBECONFIG** and updates the **PATH** environment
variable.  It may be useful in some cases to stick these in your user profile.

### Log Files

The following log files are produced:
```
[user@kvm-host workspace]$ ls -lt *log
-rw-rw-r--. 1 luke luke   409491 Oct 23 18:36 create-ocp.log
-rw-rw-r--. 1 luke luke   654998 Oct 23 19:06 deploy-ocs-ci.log
-rw-rw-r--. 1 luke luke  1144731 Oct 22 23:23 ocs-ci.git.log
-rw-rw-r--. 1 luke luke    18468 Oct 23 18:38 setup-ocs-ci.log
-rw-rw-r--. 1 luke luke 23431620 Oct 23 18:35 terraform.log
-rw-rw-r--. 1 luke luke 29235845 Oct 25 00:30 test-ocs-ci.log
```

OCS-CI log files are located here per OCP release:
```
[user@kvm-host workspace]$ ll logs-ocs-ci/4.6/
drwxrwxr-x. 3 luke luke      19 Dec  1 20:01 logs-ocs-ci/4.6/ocs-ci-logs-1606874505
-rw-rw-r--. 1 luke luke    3513 Dec  1 20:01 logs-ocs-ci/4.6/run-1606874505-config.yaml
-rw-rw-r--. 1 luke luke 8500450 Dec  2 10:31 logs-ocs-ci/4.6/test_workloads_1606874505_report.html
```

### Remote Webconsole Support

The cluster create command outputs webconsole information which should look something
like the first entry below.  This information needs to be added to your /etc/hosts file
or MacOS equivalent defining the IP Address of the KVM host server.  You must generate
the companion *oauth* definition as shown below following the same pattern.
```
<ip kvm host server> console-openshift-console.apps.test-ocp4-5.tt.testing oauth-openshift.apps.test-ocp4-5.tt.testing
```
The browser should prompt you to login to the OCP cluster.  The user name is **kubeadmin** and
the password is located in the file **<path-to-workspace>/auth/kubeadmin-password**.

## Adding and removing ocs-ci patches

Patches are located in **files/ocs-ci**.  Patches are applied in order based on their
file names by **ocs-ci-setup.sh**.  The convention is ocs-ci-nn-PRXXX-description.patch.

### Procedure to **add** a patch for ocs-ci

1.  Set ocs-upi-kvm environment variables, including PLATFORM=<kvm|powervs>
2.  create-ocp.sh, setup-ocs-ci.sh
3.  cd src/ocs-ci and make code changes
4.  git diff <files you changed> > ../../files/ocs-ci/ocs-ci-03-PR<number>-<description>.patch
5.  cd ../../ && rm -rf src/ocs-ci && git submodule update --init
6.  cd scripts
7.  ./setup-ocs-ci.sh
8.  Verify that all patches applied successfully.  If not, go back to step 3.
9.  ./deploy-ocs-ci.sh
10.  ./test-ocs-ci.sh

Note: the files you change may be included in other patches, so it is important that your
patch is numbered, so that it is applied last, so that previous patches don't have to be re-done.
In the example above, the highest numbered pre-existing patch is ocs-ci-02-xxx.

You should **not** change the src/ocs-ci submodule hash when adding a patch.

### Procedure to **remove** a patch for ocs-ci

1.  Remove desired patch(es) from files/ocs-ci
2.  rm -rf  src/ocs-ci
3.  git submodule update --init
4.  cd src/ocs-ci
5.  git checkout master (or specific commit that includes all patches that were removed)
6.  cd scripts && ./setup-ocs-ci.sh
7.  Rebase all ocs-ci patches in files/ocs-ci/ that are broken
8.  Replace broken patches in files/ocs-ci
9.  git add src/ocs-ci
10.  git commit
11.  rm -rf src/ocs-ci && git submodule update --init
12.  Set project environment variables including PLATFORM
13.  cd scripts
14.  ./create-ocp.sh
15.  ./setup-oci-ci.sh
16.  Make sure all patches were applied.   If not go back to step 7
17.  ./deploy-ocs-ci.sh
18.  ./test-ocs-ci.sh


## Crontab Automation

The following two files have been provided:

* cron-ocs.sh
* test-cron-ocs.sh

The **cron-ocs.sh** script is the master script that is invoked by **crontab**.

The **test-cron-ocs.sh** script is invoked by cron-ocs.sh and provides the
end-to-end OCP/OCS command flow.  Presently, this script invokes tier tests
2, 3, 4, 4a, 4b and 4c.  You can limit the tests to a subset by editing this file.

These scripts are located at **samples/cron** directory. 

To setup crontab automation, you must:

1.  Create *test* user account with sudo authority and login to it
2.  git clone this project in $HOME and invoke **scripts/helper/set-passwordless-sudo.sh**
3.  Place the required files defined by the ocs-upi-kvm project in $HOME
4.  Copy the two cron scripts listed above to $HOME
5.  Edit environment variables at the top of *test-cron-ocs.sh*:

```
# For KVM

export RHID_USERNAME=<Your RedHat Subscription id>
export RHID_PASSWORD=<Your RedHat Subscription password>
export IMAGES_PATH=/home/libvirt/images
```
```
# For PowerVS

export RHID_USERNAME=<Your RedHat Subscription id>
export RHID_PASSWORD=<Your RedHat Subscription password>
export PLATFORM=powervs
export PVS_API_KEY=<ibm cloud powervs api key>
export PVS_SERVICE_INSTANCE_ID=<ibm cloud powervs service instance id>
export PVS_SUBNET_NAME=<ibm cloud powervs subnet>
```
6.  Invoke **crontab -e** and enter the following two lines:

```
SHELL=/bin/bash 
0 0 * * * cd <workspace> && ./cron-ocs.sh
```

**Best practice for powervs is to allocated a dedicated subnet for testing due to cluster destroy issues**

The example above will invoke cron-ocs.sh every 24 hours at midnight local time.

Log files are written to the **logs** directory under the user's home directory.

## Troubleshooting

### Terraform Module Issues

This project may use a different version of **Terraform** and **GO** than other projects, so it is a
best practice not to switch back and forth between different terraform projects.

This project supports multiple versions of OCP requiring the use of multiple versions of the same
Terraform module.  As a result, this project builds more Terraform modules than a lot of
other OCP projects.  These modules are placed in the
local terraform registry **~/.terraform.d**.  This local registry is defined by Terraform, so the
terraform modules created by one project may be used by another.

This project only builds Terraform modules once to save time.  If a Terraform module is missing,
then you can force the tool to rebuild the requisite Terraform
modules by removing the local terraform repository like this:

```
rm -rf ~/.terraform.d
rm -rf terraform
```

This tool also automates the installation of the **libvirt** and **KVM**.  Other subsystems configured
are **networking**, **ports**, **nftables**, **dns overlays**, **ip forwarding**, **firewalls** which disables
**iptables**, and **haproxy**.  This also is just performed once based on the presence of a file.  You
can force this toolset to reconfigure these items by removing the following file.

```
rm -f ~/.kvm_setup
```

Note if a *ocs-upi-kvm code change introduces a change to the host configuration*, it will automatically
be applied when the ocs-upi-kvm project is refreshed with new code.  The **.kvm_setup** file contains
a generation count controlling when the code is re-run.

It is safe to re-run the steps above between cluster creations.  It will just take longer.

### Terraform Virtual Network Issues

If you see the following error within the first minute or two after invoking terraform:
```
Error: Error creating libvirt network: virError(Code=89, Domain=47, Message='COMMAND_FAILED: '/usr/sbin/iptables -w10 -w --table filter --insert LIBVIRT_INP --in-interface virbr5349 --protocol tcp --destination-port 67 --jump ACCEPT' failed: iptables: No chain/target/match by that name.
```
The problem is that the **bastion** node cannot communicate with systemd service **libvirtd**.  There are two resolutions:
```
sudo shutdown -Fr now
```
OR (in the order shown)
```
sudo systemctl restart nftables
sudo systemctl restart firewalld
sudo systemctl restart libvirtd
```
