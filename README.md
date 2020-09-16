# Purpose

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

## Scripts

- create-ocp.sh
- setup-ocs-cicd.sh
- run-ocs-cicd.sh
- destroy-ocs.sh

The scripts above correspond to high level tasks of OCS-CI.  They are intended to
be invoked from an automation test script such as might be deployed with Jenkins
and are designed to run unattended.  The scripts are listed in the order that
they are expected to be run.

This project uses git submodules: ocp-power-automation/ocp4-upi-kvm and
red-hat-storage/ocs-ci.  This project should be cloned to instantiate
submodules as shown below.
  
```
git clone https://github.com/ocp-power-automation/ocs-upi-kvm --recursive /root/ocs-upi-kvm

or

git clone https://github.com/ocp-power-automation/ocs-upi-kvm.sh /root/ocs-upi-kvm
cd /root/ocs-upi-kvm
git submodule update --init
```

## Required Environment Variables

- RHID_USERNAME=xxx
- RHID_PASSWORD=yyy

## Required Files

- ~/pull-secret.txt
- ~/$BASTION_IMAGE

The bastion image is a prepared image downloaded from the Red Hat Customer Portal following these
[instructions](https://github.com/ocp-power-automation/ocp4-upi-kvm/blob/master/docs/prepare-images.md).
It is named by the environment variable BASTION_IMAGE which has a default
value of "rhel-8.2-update-2-ppc64le-kvm.qcow2".  This is the name of the file downloaded
from the RedHat website.

## Optional Environment Variables with Default Values

- BASTION_IMAGE=${BASTION_IMAGE:="rhel-8.2-update-2-ppc64le-kvm.qcow2"}
- OCP_VERSION=${OCP_VERSION:="4.4"}
- CLUSTER_DOMAIN=${CLUSTER_DOMAIN:="tt.testing"}
- MASTER_DESIRED_CPU=${MASTER_DESIRED_CPU:="4"}
- MASTER_DESIRED_MEM=${MASTER_DESIRED_MEM:="16384"}
- WORKER_DESIRED_CPU=${WORKER_DESIRED_CPU:="4"}
- WORKER_DESIRED_MEM=${WORKER_DESIRED_MEM:="16384"}
- WORKERS=${WORKERS:=2}
- IMAGES_PATH=${IMAGES_PATH:="/var/lib/libvirt/images"}
- OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE=${OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE=""}
- DATA_DISK_SIZE=${DATA_DISK_SIZE:=100}
- BOOT_DISK_SIZE=${BOOT_DISK_SIZE:=32}   

Disk sizes are in GBs.

Set a new value like this:
```
export OCP_VERSION=4.5
```

The environment variable OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE is defined by
Red Hat.  It instructs the openshift installer to use a specific image.  This is
necessary for OCP 4.4 and 4.5 as the installer by default applies the latest available image.
The create_ocp.sh script sets this environment variable for OCP 4.4 and OCP 4.5 provided that
it is not set when the create script is invoked.  This environment variable is not set
by the tool for OCP 4.6 as this release is still under development.  In this case,
the latest available image will be used.

## Post Install Setup

Add the following to the root user's profile to enable the use of the **oc** command.
```
export KUBECONFIG=~/auth/kubeconfig
```

## Webconsole Support

Using the example above, on the remote server where you intend to use Firefox or Safari,
add the following to your /etc/hosts file or MacOS equivalent.
```
<ip kvm host server> console-openshift-console.apps.test-ocp4.5.tt.testing oauth-openshift.apps.test-ocp4.5.tt.testing
```
The browser should prompt you to login to the OCP cluster.  The user name is kubeadmin and
the password is located in the file ~/auth/kubeadmin-password on the KVM host server.

