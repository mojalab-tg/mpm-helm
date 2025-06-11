# Mojaloop Payment Manager (MPM) helm chart deployment on microk8s

## Infrastructure Setup

### Hardware Requirement
Prepare a virtual machine with following requirement:
- vCPU : min 4, max 8
- RAM : 16Gb
- Disk : min 50Gb, max 100Gb
- OS : Ubuntu Server Latest LTS version

### Other supported OS
You can une other linux server that surrport snapd. 

For enabling snapd Microk8s on Red Hat Enterprise Linux, follow this [https://snapcraft.io/install/microk8s/rhel](https://snapcraft.io/install/microk8s/rhel).

### When in production
For production deployment we recommend runing MPM on a microk8s HA Cluster. For this you can setup 3 similar virtual machines and use microk8s HA features.


## Microk8s Setup

### 1 Install microk8s
```bash
# Installation
sudo snap install microk8s --classic

# Add user
sudo usermod -a -G microk8s $USER
sudo chown -f -R $USER ~/.kube
newgrp microk8s

# Check microk8s status
microk8s status --wait-ready

# Create aliases
sudo snap alias microk8s.kubectl kubectl
sudo snap alias microk8s.helm3 helm
```

### 2 Clustering
Make sure all the nodes have microk8s installed and can reach each other on the network.
```bash
# On first (main) node run command to get token.
# This command also generate a join command you can copy-paste on the secondary nodes.
# Repeat the command for each node you have to add to the cluster.
microk8s add-node

# On other nodes
microk8s join <FIRST_NODE_IP>:25000/<token>
```

### 3 Enable required addons
```bash

# Base addons
sudo microk8s enable dashboard dns helm3 hostpath-storage ingress community

# Role-Based Access Control for authorisation
sudo microk8s enable rbac
## Enable rbac for dashboard
sudo kubectl create serviceaccount dashboard-admin -n kube-system
sudo kubectl create clusterrolebinding dashboard-admin --clusterrole=cluster-admin --serviceaccount=kube-system:dashboard-admin
## Genarate and save access token. Use this token to access kubenetes dashboard in web browser
sudo kubectl create token dashboard-admin -n kube-system --duration=8760h > dashbord-admin-token

# Local Docker images registry. Useful for custum mojaloop-core-conector build
microk8s enable registry

# Metrics and monitoring
microk8s enable observability metrics-server
```

### 4 Utility commands

The command assume you set aliases for microk8s.kubectl

```bash
# Enable proxy for external web access to the kubernetes dashboard 
microk8s dashboard-proxy

# See pods
sudo kubectl get pods --all-namespaces # For all pods
sudo kubectl get pods -n your_namespace # For specific namespace

# Show Services
sudo kubectl get services -n your_namespace

# See Logs
kubectl logs <pod-name>

```

## Configure and deploy pm4ml helm chart

### Get the helm chart

```bash
# Clone pm4ml git repository. Choose latest well tested release
## Replace [branch_or_release] by actual release version.
## Curent official release verstion is v10.2.1
## git clone https://github.com/mojalab-tg/mpm-helm.git -b [branch_or_release] mpm

## Please use this repository and branch for a version tested on microk8s
git clone https://github.com/mojalab-tg/mpm-helm.git -b microk8s mpm

```

### Prepare domain names
Create folowing domainnames on your internal and external DNS systems. Replace de domain name by one corresponding to your organisation domain name.
  
- portal.mpm.example.com : Web UI to acces your MPM
  - Private DNS
  - Microk8s Ingress IP

- sdk.mpm.example.com : External endpoint to Mojaloop Hub
  - Public DNS
  - Public IP NATed or Proxyed to microk8s ingress IP

- registry.mpm.example.com : Docker registry
  - Private DNS
  - Microk8s Ingress IP

Also create folowing domain if you plan to use the backend simulator module instead of an integration to your actual CBS

- sim.mpm.example.com : Web UI of Simulation Backend
  - Private DNS
  - Microk8s Ingress IP

### Edit MPM chart values
```bash
# cd into the MPM chart directory
cd mpm/mojaloop-payment-manager

# Duplicate the values.yaml file for dev or production
##cp values.yaml values-dev.yaml ## For sandbox or dev
##cp values.yaml values-prod.yaml ## For production
cp values.yaml values-dev.yaml

# Edit your deployment file and set appropriate value for your environement.
nano values-dev.yaml
## Mainly, edit the folowing values:
## [pending edit]
```

### Update dependencies and install 
```bash
# While in ~/mpm/mojaloop-payment-manager directory :

# Update helm dependencies
sudo helm dep up

# Test deployment and fix evantual issues
sudo helm install pm4ml . -f values-dev.yaml -n mpm --create-namespace --dry-run --debug

# Install the chart if test deploy has no issue. This assume release name is pm4ml and namespace is mpm
sudo helm install pm4ml . -f values-dev.yaml -n mpm --create-namespace

# Manualy init and unseal vault; run :
## You can confirm vault is successfully initiated and unsealed by displaying the pod's logs
sudo bash ../vault/init-vault.sh mpm pm4ml

```