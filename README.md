# Overview

Provide scripts enabling the automation of OCS-CI on IBM Power Servers,
including the ability to create an OCP cluster, run OCS-CI tests, and
destroy OCS (and OCP).  OCS-CI provides a deployment option to install
OpenShift Container Storage on the given worker nodes based on
Red Hat Ceph Storage.

Parameters related to the definition of the cluster such as the
OpenShift Version and the number and size of worker nodes are specified
via environment variables to the scripts listed below.

The goal of this project is to provide the primitives that are needed
to enable OCS-CI on Power Servers.  These scripts form a framework for the
development and validation of OpenShift clusters and operators.

This project utilizes KVM to create a OpenShift Cluster running in VMs.  This
project runs on baremetal servers as well as PowerVM and PowerVS based servers
provided that a large enough LPAR is allocated.

## User Requirements

This project may be run by non-root users with **sudo** authority.
*passwordless* sudo access should be setup for this user, so that the scripts
don't prompt for a password while running.  A helper script is provided
for this purpose at **scripts/helper/set-passwordless-sudo.sh**.  There are no
command arguments for this script and it should be run once during initial setup.

Non-root users must use the **sudo** command with **virsh** to see VMs.

## Scripts

- create-ocp.sh [ --retry ]
- setup-ocs-ci.sh
- deploy-ocs-ci.sh
- test-ocs-ci.sh [ --tier <0,1,...> ]
- teardown-ocs-ci.sh
- destroy-ocp.sh

The scripts above correspond to high level tasks of OCS-CI.  They are intended to
be invoked from an automation test script such as *Jenkins*
and are designed to run unattended.  The scripts are listed in the order that
they are expected to be run.

This project uses git submodules:

- github.com/ocp-power-automation/ocp4-upi-kvm 
- github.com/red-hat-storage/ocs-ci

These underlying projects must be instantiated before the create, setup, deploy,
test, and teardown scripts are used.  The user is expected to setup the submodules
before invoking these scripts.  The *sample* scripts described in the next section
instantiate the submodules as they invoke create, setup, and deploy in a sequence.

There are two ways to instantiate submodules as shown below:
```
git clone https://github.com/ocp-power-automation/ocs-upi-kvm --recursive
cd ocs-upi-kvm/scripts
```
**OR**
```
git clone https://github.com/ocp-power-automation/ocs-upi-kvm.sh
cd ocs-upi-kvm
git submodule update --init
```
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

The script **destroy-ocp.sh** which recompletely removes ocp and ocs.

The script **create-ocp.sh** will also remove an existing OCP cluster if one is present
before creating a new one as *only one OCP cluster is supported on the host KVM server
at a time*.  This is true even if the cluster was created by another user, so if you are
concerned with impacting other users run this command first, *sudo virsh list --all*.

## Sample scripts

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

## Required Environment Variables

- RHID_USERNAME=xxx
- RHID_PASSWORD=yyy

**OR**

- RHID_ORG=ppp
- RHID_KEY=qqq

## Project Workspace

This project is designed to be used in an automated test framework like Jenkins which utilizes
dedicated workspaces to run jobs in parallel on the same server.  As such, all input, output,
and internally generated files are restricted to the specific workspace instance that
is allocated to run the job.  For this project, that workspace is assumed to be 
the *parent* directory of the cloned project **ocs-upi-kvm** itself.

## Required Files

These files should be placed in the workspace directory.

- ~/auth.yaml
- ~/pull-secret.txt
- ~/$BASTION_IMAGE

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
[instructions](https://github.com/ocp-power-automation/ocp4-upi-kvm/blob/master/docs/prepare-images.md).
It is named by the environment variable BASTION_IMAGE which has a default
value of "rhel-8.2-update-2-ppc64le-kvm.qcow2".  This is the name of the file downloaded
from the RedHat website.

When preparing the bastion image above, the root password must be set to **123456**.

## Optional Environment Variables with Default Values

- OCP_VERSION=${OCP_VERSION:="4.5"}
- CLUSTER_DOMAIN=${CLUSTER_DOMAIN:="tt.testing"}
- BASTION_IMAGE=${BASTION_IMAGE:="rhel-8.2-update-2-ppc64le-kvm.qcow2"}
- MASTER_DESIRED_CPU=${MASTER_DESIRED_CPU:="4"}
- MASTER_DESIRED_MEM=${MASTER_DESIRED_MEM:="16384"}
- WORKER_DESIRED_CPU=${WORKER_DESIRED_CPU:="16"}
- WORKER_DESIRED_MEM=${WORKER_DESIRED_MEM:="65536"}
- WORKERS=${WORKERS:=3}
- IMAGES_PATH=${IMAGES_PATH:="/var/lib/libvirt/images"}
- OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE=${OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE:=""}
- DATA_DISK_SIZE=${DATA_DISK_SIZE:=256}
- DATA_DISK_LIST=${DATA_DISK_LIST:=""}
- FORCE_DISK_PARTITION_WIPE=${FORCE_DISK_PARTITION_WIPE:="false"}

Disk sizes are in GBs.

Set a new value like this:
```
export OCP_VERSION=4.6
```

The environment variable OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE is defined by
Red Hat.  It instructs the openshift installer to use a specific image.  This is
necessary for OCP 4.4 and 4.5 as the
[latest available image](https://mirror.openshift.com/pub/openshift-v4/ppc64le/clients/ocp-dev-preview/)
is installed by default.  That is, the latest available image for the release under development.

The **create_ocp.sh** script internally sets this environment variable for OCP 4.4 and OCP 4.5
provided that it is not set by the user.  This environment variable is not set
automatically for OCP 4.6 as this release is still under development.

Set a specific daily build like this:
```
REGISTRY="registry.svc.ci.openshift.org/ocp-ppc64le/release-ppc64le"
export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="$REGISTRY:4.6.0-0.nightly-ppc64le-2020-09-27-075246"
```

The script **create-ocp.sh** will add a data disk to each worker node.  This disk is presented
inside the worker node as /dev/vdc.  In the KVM host server OS, the data disk is backed 
by either a file or a physical disk partition.  If you specify the environment
variable DATA_DISK_LIST, then the named physical disk partitions (/dev) will be used.
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


## Post Install

### Configure the use of the **oc** command

Add the following to the user's profile to enable the use of the **oc** command.
```
export KUBECONFIG=<path-to-workspace>/auth/kubeconfig
```
As noted above, the parameter <path-to-workspace> is the *parent* directory
of the **ocs-upi-kvm** directory.  For example, if ocs-upi-kvm is installed at
~/workspace/ocs/ocs-upi-kvm, then the export statement would be:

```
export KUBECONFIG=~/workspace/ocs/auth/kubeconfig
```

### Log Files

Several log files are located in the workspace.

### Build artificacts including oc command and kubeconfig

This project downloads and installs GO into the workspace.  It uses the go command to
compile terraform and terraform Modules that are used during the creation of the OCP cluster.
The versions of GO and Terraform are specific to the OCP release.  The scripts will
automatically download and update these binaries as required.

If you remove the workspace after the cluster is created, then you will not be able 
to run the oc command as it is included in the workspace along with kubeconfig.  These
are the relevant commands that should be relocated if you want to destroy the workspace
after creating a cluster.  Again using the example cluster above:

```
cp ~workspace/ocs/bin ~/bin
cp -r ~workspace/ocs/auth ~
```

### Remote Webconsole Support

The cluster create command should output webconsole information which should look something
like the first entry below.  The second entry which is related to oauth you will have to produce
following the pattern shown below.  On the your laptop, you should add the console URL to your
/etc/hosts file or MacOS equivalent defining the IP Address of the KVM server.

```
<ip kvm host server> console-openshift-console.apps.test-ocp4-5.tt.testing oauth-openshift.apps.test-ocp4-5.tt.testing
```
The browser should prompt you to login to the OCP cluster.  The user name is kubeadmin and
the password is located in the file <path-to-workspace>/auth/kubeadmin-password on the KVM host server.

