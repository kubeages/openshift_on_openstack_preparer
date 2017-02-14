# openshift_on_openstack_preparation_script
Modular script to make easier the preparation for the deployment of OpenShift Container Platform on OpenStack.

In order to make it work, please copy this script into a folder with these another files:
- the OpenStack RC files (for Openshift project and optionally for Admin project)
- the QCOW2 RHEL file for image creation (optional if this is already created on the environment)

Releases:
- v0.1: This release creates everything that is needed to prepare an OCP on OpenStack deployment. 
- v0.2: This release improves three modules: security groups, instances creation, floating IPs.

Note: 
- This script doesn´t install prereqs or OCP itself. It´s conceived to help to prepare the environment for OCP deployment.
- This script is not intended for flannel based deployments. Anyway, it can be easily adjusted for that purpose.

Sources:
- This script has been inspired by the excellent document "Deploying Red Hat OpenShift Container Platform 3 on Red Hat OpenStack Platform", authored by Mark Lamourine, Ryan Cook and Scott Collier. Link: https://access.redhat.com/articles/2743631
