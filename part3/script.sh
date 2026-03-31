#!/bin/bash

set -e  # Arrête le script si une commande échoue

echo "=== Mise à jour du système ==="
apt-get update -y
apt-get upgrade -y

echo "=== Installation des dépendances ==="
# apt-transport-https : nécessaire pour ajouter des dépôts HTTPS
# ca-certificates : pour vérifier les certificats SSL
# gnupg : pour gérer les clés GPG des dépôts
# lsb-release : pour détecter la distribution Linux
apt-get install -y \
    curl \
    wget \
    git \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release

echo "=== Installation de Docker ==="
curl -fsSL https://get.docker.com | sh -
systemctl enable docker # démarre Docker au démarrage du système
systemctl start docker # démarre Docker immédiatement (pas besoin de redémarrer la machine)
usermod -aG docker vagrant  # permet d'utiliser docker sans sudo pour l'utilisateur 'vagrant'

echo "=== Installation de kubectl ==="
curl -LO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/arm64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/

echo "=== Installation de K3d ==="
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

echo "=== Installation de Argo CD CLI ==="
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-arm64
chmod +x /usr/local/bin/argocd

echo "=== Création du cluster K3d ==="
# On retire l'exposition sur le port 8080 car on va utiliser ce port directement pour ArgoCD avec un tunnel.
k3d cluster create mycluster \
    --port "8888:8888@loadbalancer"

echo "=== Configuration de kubectl ==="
k3d kubeconfig merge mycluster --kubeconfig-switch-context

echo "=== Création des namespaces ==="
kubectl create namespace argocd
kubectl create namespace dev

echo "=== Installation de Argo CD ==="
# Utilisation de --server-side pour éviter la limite de 256ko (262144 bytes) sur les annotations K8s
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --server-side --force-conflicts

echo "=== Attente que Argo CD soit prêt ==="
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

echo "=== Récupération du mot de passe Argo CD ==="
echo "Mot de passe admin Argo CD :"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""

echo "=== Configuration du Tunnel Argo CD ==="
# On lance le port-forward en arrière-plan pour qu'ArgoCD réponde sur le port 8080 dès le lancement
nohup kubectl port-forward svc/argocd-server -n argocd --address 0.0.0.0 8080:443 > /dev/null 2>&1 &

echo "=== Installation terminée ! ==="
echo "Cluster K3d : $(k3d cluster list)"
echo "Nodes : $(kubectl get nodes)"
echo "Namespaces : $(kubectl get ns)"