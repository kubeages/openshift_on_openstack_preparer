##### Quick OCP on OSP preparation installer
##### Opinionated deployment tool to make OCP deployment on OSP a simpler thing
##### v0.1 by Antonio Gallego - agallego@redhat.com
##### Red Hat - 2016
#####
##### Files that need to be place in the same path that this installer:
##### - keystonerc_admin - credentials to login into admin project
##### - keystonerc_openshift - credentials to login into openshift project
##### - rhel-guest-image-xxxx.qcow2 - image used to create instances

echo -e "\n##### Welcome to OpenShift on OpenStack quick installer #####\n\n"

##### Configuration part
##### Fill these variables based on your own environment

#Get OpenShift project ID running "openstack project list"
OCP_TENANT_ID=59b2dc5bf6d347d39f247ed18d0dba6c

#DNS server details
NAMESERVER=192.168.1.14

#Public network details
PUBLIC_NETWORK_NAME=public_network
PUBLIC_SUBNET_NAME=public_subnet
PUBLIC_NETWORK_POOL_START=192.168.1.200
PUBLIC_NETWORK_POOL_END=192.168.1.240
PUBLIC_NETWORK_GATEWAY=192.168.1.1
PUBLIC_SUBNET_RANGE=192.168.1.0/24

#OpenShift private network details
OCP_NETWORK_NAME=openshift
OCP_NETWORK_RANGE=172.18.10.0/24

#RHEL image details
RHEL_FILE_NAME=rhel-guest-image-7.3-35.x86_64.qcow2
RHEL_IMAGE_NAME=rhel73

#OpenShift instances details
OCP_DOMAIN=ageslab.com
OCP_BASTION="bastion"
OCP_LB="lbmaster lbapps"
OCP_MASTERS="master1 master2 master3"
OCP_INFRANODES="infranode1 infranode2"
OCP_APPNODES="appnode1 appnode2"
OCP_ALLNODES="$OCP_BASTION $OCP_LB $OCP_MASTERS $OCP_INFRANODES $OCP_APPNODES"

#Volumes details
VOLUME_SIZE=30 #specify the volume size for docker disk in the instances
VOLUME_TYPE=nfs #specify the volume type to user in the docker disks creation

#Keypair details
KEYPAIR_NAME=ocpkp

##### OSP preparation part

##### External network configuration
read -p "Do you wish to configure the external network? (y/n) " answer
if [ "$answer" = "y" ]; then
  echo -e "\n##### Configuring external network\n"
  source ./keystonerc_admin
  neutron net-create $PUBLIC_NETWORK_NAME --shared --router:external=True
  neutron subnet-create $PUBLIC_NETWORK_NAME --name $PUBLIC_SUBNET_NAME --allocation-pool start=$PUBLIC_NETWORK_POOL_START,end=$PUBLIC_NETWORK_POOL_END --disable-dhcp --gateway $PUBLIC_NETWORK_GATEWAY $PUBLIC_SUBNET_RANGE
  neutron net-list
fi

##### RHEL image creation
read -p "Do you wish to create a RHEL image? (y/n) " answer
if [ "$answer" = "y" ]; then
  echo -e "\n##### Creating image\n"
  source ./keystonerc_admin
  glance image-create --name $RHEL_IMAGE_NAME --file $RHEL_FILE_NAME --visibility public --disk-format qcow2 --container-format bare --progress
fi

##### OpenShift Flavors creation
read -p "Do you wish to create OpenShift flavors? (y/n) " answer
if [ "$answer" = "y" ]; then
  echo -e "\n##### Creating OpenShift flavors\n"
  source ./keystonerc_admin
  nova flavor-create --is-public false ocpbastion auto 2048 20 1
  nova flavor-create --is-public false ocplb auto 4096 20 1
  nova flavor-create --is-public false ocpmaster auto 8192 30 2
  nova flavor-create --is-public false ocpinfranode auto 8192 30 2
  nova flavor-create --is-public false ocpappnode auto 8192 30 1

  nova flavor-access-add ocpbastion $OCP_TENANT_ID
  nova flavor-access-add ocplb $OCP_TENANT_ID
  nova flavor-access-add ocpmaster $OCP_TENANT_ID
  nova flavor-access-add ocpinfranode $OCP_TENANT_ID
  nova flavor-access-add ocpappnode $OCP_TENANT_ID
fi

##### OpenShift network creation
read -p "Do you wish to create a network for OpenShift nodes? (y/n) " answer
if [ "$answer" = "y" ]; then
  echo -e "\n##### Creating OpenShift network\n"
  source ./keystonerc_openshift
  neutron net-create $OCP_NETWORK_NAME-network
  neutron subnet-create --name $OCP_NETWORK_NAME-subnet --dns-nameserver ${NAMESERVER} $OCP_NETWORK_NAME-network $OCP_NETWORK_RANGE
  neutron router-create $OCP_NETWORK_NAME-router
  neutron router-interface-add $OCP_NETWORK_NAME-router $OCP_NETWORK_NAME-subnet
  neutron router-gateway-set $OCP_NETWORK_NAME-router $PUBLIC_NETWORK_NAME
  nova net-list
fi

##### OpenShift network creation
read -p "Do you wish to create a keypair for accessing OpenShift nodes? (y/n) " answer
if [ "$answer" = "y" ]; then
  source ./keystonerc_openshift
  ssh-keygen -f $KEYPAIR_NAME -N ""
  nova keypair-add --pub-key $KEYPAIR_NAME.pub $KEYPAIR_NAME
fi

##### Cloud init files creation
read -p "Do you wish to create cloud init files for OpenShift nodes? (y/n) " answer
if [ "$answer" = "y" ]; then
echo -e "\n##### Creating configuration files for instances cloud init\n"
echo -e "\nInstances list: $OCP_ALLNODES\n"
function generate_userdata() {
# HOSTNAME=$1
# DOMAIN=$2
cat <<EOF
#cloud-config
hostname: $1.$2
fqdn: $1.$2
EOF
}
mkdir cloudinit
for HOST in $OCP_ALLNODES
do
  generate_userdata ${HOST} ${OCP_DOMAIN} > ./cloudinit/${HOST}.yaml
done
fi

##### Docker volumes creation
read -p "Do you wish to create docker volumes for the master nodes? (y/n) " answer
if [ "$answer" = "y" ]; then
echo -e "\n##### Creating docker volumes for master nodes\n"
source ./keystonerc_openshift
MASTER_INSTANCES_DOCKER_VOLUMES=true
for HOST in $OCP_MASTERS
do
cinder create --volume_type $VOLUME_TYPE --name $HOST-docker ${VOLUME_SIZE}
done
fi

read -p "Do you wish to create docker volumes for the other nodes? (y/n) " answer
if [ "$answer" = "y" ]; then
  source ./keystonerc_openshift
echo -e "\n##### Creating docker volumes for infranodes\n"
for HOST in $OCP_INFRANODES
do
cinder create --volume_type $VOLUME_TYPE --name $HOST-docker ${VOLUME_SIZE}
done
echo -e "\n##### Creating docker volumes for appnodes\n"
for HOST in $OCP_APPNODES
do
cinder create --volume_type $VOLUME_TYPE --name $HOST-docker ${VOLUME_SIZE}
done
fi

##### Security groups creation
read -p "Do you wish to create security groups? (y/n) " answer
if [ "$answer" = "y" ]; then
source ./keystonerc_openshift
echo -e "\n##### Creating security group for bastion\n"
neutron security-group-create bastion-sg
neutron security-group-rule-create bastion-sg --protocol icmp
neutron security-group-rule-create bastion-sg \
--protocol tcp --port-range-min 22 --port-range-max 22
echo -e "\n##### Creating security group for load balancer\n"
neutron security-group-create lb-sg
neutron security-group-rule-create lb-sg --protocol icmp
neutron security-group-rule-create lb-sg \
--protocol tcp --port-range-min 22 --port-range-max 22
neutron security-group-rule-create lb-sg \
--protocol tcp --port-range-min 443 --port-range-max 443
neutron security-group-rule-create lb-sg \
--protocol tcp --port-range-min 80 --port-range-max 80
neutron security-group-rule-create lb-sg \
--protocol tcp --port-range-min 9000 --port-range-max 9000
echo -e "\n##### Creating security group for master nodes\n"
neutron security-group-create master-sg
neutron security-group-rule-create master-sg --protocol icmp
neutron security-group-rule-create master-sg \
--protocol tcp --port-range-min 22 --port-range-max 22 \
--remote-group-id bastion-sg
neutron security-group-rule-create master-sg \
--protocol tcp --port-range-min 10250 --port-range-max 10250 \
--remote-group-id master-sg
for PORT in 8443 8444 8053 4789 2379 10255 9000 2380 5404 5405 2224 24224
do
neutron security-group-rule-create master-sg \
--protocol tcp --port-range-min $PORT --port-range-max $PORT
done
for PORT in 10255 24224
do
neutron security-group-rule-create master-sg \
--protocol udp --port-range-min $PORT --port-range-max $PORT
done
echo -e "\n##### Creating security group for infranodes\n"
neutron security-group-create infranode-sg
neutron security-group-rule-create infranode-sg --protocol icmp
neutron security-group-rule-create infranode-sg \
--protocol tcp --port-range-min 22 --port-range-max 22 \
--remote-group-id bastion-sg
for PORT in 80 443 4789 10255
do
neutron security-group-rule-create infranode-sg \
--protocol tcp --port-range-min $PORT --port-range-max $PORT
done
neutron security-group-rule-create infranode-sg \
--protocol udp --port-range-min 10255 --port-range-max 10255 \
--remote-group-id master-sg
echo -e "\n##### Creating security group for appnodes\n"
neutron security-group-create appnode-sg
neutron security-group-rule-create appnode-sg --protocol icmp
neutron security-group-rule-create appnode-sg \
--protocol tcp --port-range-min 22 --port-range-max 22 \
--remote-group-id bastion-sg
neutron security-group-rule-create appnode-sg \
--protocol tcp --port-range-min 10255 --port-range-max 10255 \
--remote-group-id master-sg
neutron security-group-rule-create appnode-sg \
--protocol udp --port-range-min 10255 --port-range-max 10255 \
--remote-group-id master-sg
neutron security-group-rule-create appnode-sg \
--protocol tcp --port-range-min 4789 --port-range-max 4789
fi

##### OpenShift instances creation
read -p "Do you wish to create the OpenShift nodes? (y/n) " answer
if [ "$answer" = "y" ]; then
  source ./keystonerc_openshift
  echo -e "\n##### Creating bastion instance\n"
  nova boot --flavor ocpbastion --image $RHEL_IMAGE_NAME --key-name $KEYPAIR_NAME \
  --nic net-name=$OCP_NETWORK_NAME-network \
  --security-groups bastion-sg \
  --user-data ./cloudinit/$OCP_BASTION.yaml \
  $OCP_BASTION.$OCP_DOMAIN
  echo -e "\n##### Creating load balancers\n"
  for HOST in $OCP_LB ; do
    nova boot --flavor ocplb --image $RHEL_IMAGE_NAME --key-name $KEYPAIR_NAME \
    --nic net-name=$OCP_NETWORK_NAME-network \
    --security-groups lb-sg \
    --user-data ./cloudinit/$HOST.yaml \
    $HOST.$OCP_DOMAIN
  done
  echo -e "\n##### Creating master nodes instance(s)\n"
  if [ "$MASTER_INSTANCES_DOCKER_VOLUMES" = "true" ]; then
    for HOST in $OCP_MASTERS ; do
      VOLUMEID=$(cinder show ${HOST}-docker | grep ' id ' | awk '{print $4}')
      nova boot --flavor ocpmaster --image $RHEL_IMAGE_NAME --key-name $KEYPAIR_NAME \
      --nic net-name=$OCP_NETWORK_NAME-network \
      --security-groups master-sg \
      --block-device source=volume,dest=volume,device=vdb,id=${VOLUMEID} \
      --user-data ./cloudinit/$HOST.yaml \
      $HOST.$OCP_DOMAIN
    done
  else
    for HOST in $OCP_MASTERS ; do
      nova boot --flavor ocpmaster --image $RHEL_IMAGE_NAME --key-name $KEYPAIR_NAME \
      --nic net-name=$OCP_NETWORK_NAME-network \
      --security-groups master-sg \
      --user-data ./cloudinit/$HOST.yaml \
      $HOST.$OCP_DOMAIN
    done
  fi
  echo -e "\n##### Creating infra nodes instance(s)\n"
  for HOST in $OCP_INFRANODES ; do
    VOLUMEID=$(cinder show ${HOST}-docker | grep ' id ' | awk '{print $4}')
    nova boot --flavor ocpinfranode --image $RHEL_IMAGE_NAME --key-name $KEYPAIR_NAME \
    --nic net-name=$OCP_NETWORK_NAME-network \
    --security-groups infranode-sg \
    --block-device source=volume,dest=volume,device=vdb,id=${VOLUMEID} \
    --user-data ./cloudinit/$HOST.yaml \
    $HOST.$OCP_DOMAIN
  done
  echo -e "\n##### Creating app nodes instance(s)\n"
  for HOST in $OCP_APPNODES ; do
    VOLUMEID=$(cinder show ${HOST}-docker | grep ' id ' | awk '{print $4}')
    nova boot --flavor ocpappnode --image $RHEL_IMAGE_NAME --key-name $KEYPAIR_NAME \
    --nic net-name=$OCP_NETWORK_NAME-network \
    --security-groups appnode-sg \
    --block-device source=volume,dest=volume,device=vdb,id=${VOLUMEID} \
    --user-data ./cloudinit/$HOST.yaml \
    $HOST.$OCP_DOMAIN
  done
fi

##### Floating IPs creation
read -p "Do you wish to create floating IPs for the load balancers? (y/n) " answer
if [ "$answer" = "y" ]; then
  source ./keystonerc_openshift
  echo -e "\n##### Creating floating IPs\n"
  for HOST in $OCP_LB ; do  
    FLOATING_IP=$(nova floating-ip-create $PUBLIC_NETWORK_NAME | grep $PUBLIC_NETWORK_NAME | awk '{print $4}')
    nova floating-ip-associate $HOST.$OCP_DOMAIN $FLOATING_IP
  done
fi

echo -e "\n##### Thanks for using OpenShift on OpenStack quick installer #####\n\n"
