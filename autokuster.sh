#!/bin/bash

##############################################################################################################
### INSTALL COMMAND:  source <(wget -qO - https://github.com/antillgrp/autokluster/raw/master/autokuster.sh)
##############################################################################################################

# Source: http://kubernetes.io/docs/getting-started-guides/kubeadm

set -e

source /etc/lsb-release
if [ "$DISTRIB_RELEASE" != "20.04" ]; then
    echo "################################# "
    echo "############ WARNING ############ "
    echo "################################# "
    echo
    echo "This script only works on Ubuntu 20.04!"
    echo "You're using: ${DISTRIB_DESCRIPTION}"
    exit 1
fi

NC='\033[0m'; YELLOW='\033[0;33m'; GREEN='\033[0;32m'; RED='\033[0;31m'

while printf "${YELLOW}Task (1. install kubernetes master, 2. install kubernetes worker):${NC}" && read -r TASK
do pattern='[12]' && [[ $TASK =~ $pattern ]] && break 1 ||  printf>&2 'Invalid task: "%s"\n' "$TASK"; done

[[ "${TASK}" == "1" ]] && HOSTNAME_PREFIX="master" || HOSTNAME_PREFIX="worker" 

while printf "${YELLOW}IP host ${GREEN}(range 140-240) ${YELLOW}192.168.10.${NC}" && read -r H
do 
  [[ $H =~ ^[0-9]{1,3}$ ]] && [[ $H -ge 140 ]] && [[ $H -le 240 ]] && break 1 ||  
  printf>&2 'Invalid IP host: "%s"\n' "$H" 
done

hostnamectl set-hostname "$HOSTNAME_PREFIX-$H"

cat <<EOF >/etc/netplan/01-network-manager-all.yaml
# Let NetworkManager manage all devices on this system
network:
  version: 2
  renderer: NetworkManager
  ethernets:
    ens33:
      dhcp4: false
      dhcp6: false
      addresses:
      - 192.168.10.${H}/24
      routes:
      - to: default
        via: 192.168.10.2
      nameservers:
       addresses: [8.8.8.8,8.8.4.4,192.168.10.2]
EOF

printf "\n${GREEN}This script will be logged to the file ($HOME/install_$HOSTNAME_PREFIX-$H.sh.log) and to the screen${NC}\n"
exec 1> >( tee -a $HOME/install_$HOSTNAME_PREFIX-$H.sh.log ) 2>&1

#################################################################################################################################

### setup terminal
apt-get --allow-unauthenticated update
apt-get --allow-unauthenticated install -y bash-completion binutils
echo 'colorscheme ron' >> ~/.vimrc
echo 'set tabstop=2' >> ~/.vimrc
echo 'set shiftwidth=2' >> ~/.vimrc
echo 'set expandtab' >> ~/.vimrc
echo 'source <(kubectl completion bash)' >> ~/.bashrc
echo 'complete -F __start_kubectl k' >> ~/.bashrc
sed -i '1s/^/force_color_prompt=yes\n/' ~/.bashrc

echo "alias c='clear'"               >> $HOME/.bash_aliases && 
echo "alias k='kubectl'"             >> $HOME/.bash_aliases &&
echo "alias kk='kubectl -k'"         >> $HOME/.bash_aliases && 
echo "alias kak='kubectl apply -k'"  >> $HOME/.bash_aliases && 
echo "alias kdk='kubectl delete -k'" >> $HOME/.bash_aliases && 
echo "alias kaf='kubectl apply -f'"  >> $HOME/.bash_aliases && 
echo "alias kdf='kubectl delete -f'" >> $HOME/.bash_aliases && 
source $HOME/.bash_aliases

### disable linux swap and remove any existing swap partitions
swapoff -a
sed -i '/\sswap\s/ s/^\(.*\)$/#\1/g' /etc/fstab

### remove packages
kubeadm reset -f || true
crictl rm --force $(crictl ps -a -q) || true
apt-mark unhold kubelet kubeadm kubectl kubernetes-cni || true
apt-get remove -y docker.io containerd kubelet kubeadm kubectl kubernetes-cni || true
apt-get autoremove -y
systemctl daemon-reload

### install podman
. /etc/os-release
echo "deb http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_${VERSION_ID}/ /" | \
sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:testing.list
curl -L "http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_${VERSION_ID}/Release.key" | \
sudo apt-key add -
apt-get update -qq
apt-get -qq -y install podman cri-tools containers-common
rm /etc/apt/sources.list.d/devel:kubic:libcontainers:testing.list
cat <<EOF | sudo tee /etc/containers/registries.conf
[registries.search]
registries = ['docker.io']
EOF

### KUBEADMIN ###################################################################################################################

KUBE_VERSION=1.30.1

### install packages
apt-get install -y apt-transport-https ca-certificates
mkdir -p /etc/apt/keyrings
rm /etc/apt/keyrings/kubernetes-1-27-apt-keyring.gpg || true
rm /etc/apt/keyrings/kubernetes-1-28-apt-keyring.gpg || true
rm /etc/apt/keyrings/kubernetes-1-29-apt-keyring.gpg || true
rm /etc/apt/keyrings/kubernetes-1-30-apt-keyring.gpg || true
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.27/deb/Release.key | \
sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-1-27-apt-keyring.gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | \
sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-1-28-apt-keyring.gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | \
sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-1-29-apt-keyring.gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | \
sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-1-30-apt-keyring.gpg
echo > /etc/apt/sources.list.d/kubernetes.list
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-1-27-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v1.27/deb/ /" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-1-28-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-1-29-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-1-30-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list
apt-get --allow-unauthenticated update
apt-get --allow-unauthenticated install -y \
docker.io containerd kubelet=${KUBE_VERSION}-1.1 \
kubeadm=${KUBE_VERSION}-1.1 kubectl=${KUBE_VERSION}-1.1 kubernetes-cni
apt-mark hold kubelet kubeadm kubectl kubernetes-cni

### install containerd 1.6 over apt-installed-version
wget https://github.com/containerd/containerd/releases/download/v1.6.12/containerd-1.6.12-linux-amd64.tar.gz
tar xvf containerd-1.6.12-linux-amd64.tar.gz
systemctl stop containerd
mv bin/* /usr/bin
rm -rf bin containerd-1.6.12-linux-amd64.tar.gz
systemctl unmask containerd
systemctl start containerd

### containerd
cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sudo sysctl --system
sudo mkdir -p /etc/containerd

### containerd config
cat > /etc/containerd/config.toml <<EOF
disabled_plugins = []
imports = []
oom_score = 0
plugin_dir = ""
required_plugins = []
root = "/var/lib/containerd"
state = "/run/containerd"
version = 2

[plugins]

  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
    [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
      base_runtime_spec = ""
      container_annotations = []
      pod_annotations = []
      privileged_without_host_devices = false
      runtime_engine = ""
      runtime_root = ""
      runtime_type = "io.containerd.runc.v2"

      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
        BinaryName = ""
        CriuImagePath = ""
        CriuPath = ""
        CriuWorkPath = ""
        IoGid = 0
        IoUid = 0
        NoNewKeyring = false
        NoPivotRoot = false
        Root = ""
        ShimCgroup = ""
        SystemdCgroup = true
EOF

### crictl uses containerd as default
{
cat <<EOF | sudo tee /etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
EOF
}

### kubelet should use containerd
{
cat <<EOF | sudo tee /etc/default/kubelet
KUBELET_EXTRA_ARGS="--container-runtime-endpoint unix:///run/containerd/containerd.sock"
EOF
}

### start services
systemctl daemon-reload
systemctl enable containerd
systemctl restart containerd
systemctl enable kubelet && systemctl start kubelet

### init k8s
if [[ "${TASK}" == "1" ]] 
then

#### Install k9s ###############################################
curl -sS https://webinstall.dev/k9s | bash && source ~/.config/envman/PATH.env

#### Install lazydocker ########################################  
wget -qO- "https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh" | \
sed 's|$HOME/.local/bin|/usr/local/bin|' | bash && mkdir -p $HOME/.config/lazydocker/ && \
cat > $HOME/.config/lazydocker/config.yml <<EO1
# https://github.com/jesseduffield/lazydocker/blob/master/docs/Config.md
logs:
  timestamps: true
  since: '' # set to '' to show all logs
  tail: '50' # set to 200 to show last 200 lines of logs
EO1
lazydocker --version

#### Installing VSCode #########################################
apt-get update && apt install wget -y && 
wget -O vscode.deb 'https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64' && 
apt install ./vscode.deb -y && rm -f ./vscode.deb

#### kubeadm init ##############################################
rm /root/.kube/config || true
kubeadm init --kubernetes-version=${KUBE_VERSION} \
--ignore-preflight-errors=NumCPU --skip-token-print --pod-network-cidr 10.244.0.0/16 # 192.168.0.0/16

#### .kube/config ##############################################
mkdir -p ~/.kube
sudo cp -i /etc/kubernetes/admin.conf ~/.kube/config

### CNI
kubectl apply -f https://github.com/coreos/flannel/raw/master/Documentation/kube-flannel.yml
sleep 120
kubectl wait pods -n kube-flannel  -l app=flannel --for condition=Ready --timeout=180s

# kubectl apply -f https://raw.githubusercontent.com/killer-sh/cks-course-environment/master/cluster-setup/calico.yaml

# etcdctl
ETCDCTL_VERSION=v3.5.1
ETCDCTL_ARCH=$(dpkg --print-architecture)
ETCDCTL_VERSION_FULL=etcd-${ETCDCTL_VERSION}-linux-${ETCDCTL_ARCH}
wget https://github.com/etcd-io/etcd/releases/download/${ETCDCTL_VERSION}/${ETCDCTL_VERSION_FULL}.tar.gz
tar xzf ${ETCDCTL_VERSION_FULL}.tar.gz ${ETCDCTL_VERSION_FULL}/etcdctl
mv ${ETCDCTL_VERSION_FULL}/etcdctl /usr/bin/
rm -rf ${ETCDCTL_VERSION_FULL} ${ETCDCTL_VERSION_FULL}.tar.gz

### local-path-storage
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml 

# apiVersion: v1
# kind: PersistentVolumeClaim
# metadata:
#   name: local-path-pvc
# spec:
#   accessModes:
#     - ReadWriteOnce
#   storageClassName: local-path
#   resources:
#     requests:
#       storage: 128Mi

echo
echo "### COMMAND TO ADD A WORKER NODE ###"
kubeadm token create --print-join-command --ttl 0

else

kubeadm reset -f
systemctl daemon-reload
service kubelet start

echo
echo "EXECUTE ON MASTER: kubeadm token create --print-join-command --ttl 0"
echo "THEN RUN THE OUTPUT AS COMMAND HERE TO ADD AS WORKER"
echo

fi

if [[ "$(ip addr show ens33 | awk '/inet / {print $2}' | cut -d/ -f1)" != "192.168.10.$H" ]]; then
printf "${YELLOW}IP address will change to 192.168.10.$H.${NC}"
printf "${YELLOW} If connected through SSH, connect to the new IP.${NC}"
netplan apply
fi