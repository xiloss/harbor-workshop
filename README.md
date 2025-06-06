# HARBOR WORKSHOP

## Table of Contents

- [Foreword](#foreword)
- [Clone sources](#clone-the-following-repositories)
- [Install Requirements](#install-requirements)
  - [Using ubuntu](#when-using-ubuntu)
    - [sudo Setup](#setup-sudo-with-no-password-or-your-current-user-optional)
    - [Ensure packages](#ensure-packages)
    - [Ensure docker](#ensure-docker-installation)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
    - [kind](#install-kind)
    - [kubectl](#install-kubectl-cli)
    - [helm](#install-helm)
    - [argocd cli](#install-argocd-cli-optional)
  - [Setup](#setup)
    - [kind cluster](#create-kind-cluster)
    - [ingress controller](#install-ingress-controller)
    - [certmanager](#install-and-configure-cert-manager)
    - [harbor](#install-harbor)
      - [Verify the Installation](#verifying-the-installation)
      - [Notes](#notes)
  - [Pushing Containers](#pushing-containers)
  - [Local Registry](#running-a-local-registry)
    - [Local Registry Setup](#local-registry-setup)
    - [Local Registry in Harbor](#configuring-local-registry-in-harbor-console)
    - [Replication Rules](#creating-replication-rules)
  - [Dragonfly](#installing-dragonfly-to-start-testing-image-distribution)
  - [Gitea](#installing-gitea-for-cluster-cicd-repositories)
  - [Argocd](#installing-argocd-on-kind)
    - [Argocd gitea setup](#argo-gitea-setup)
  - [Flux](#installing-fluxcd2-on-kind)
    - [Fluxcd gitea setup](#flux-gitea-setup)
- [Experiment Application - Demo](#the-experiment-demo)
  - [Harbor Users](#create-harbor-users)
  - [Flux Demo App Repo Setup](#create-new-repository-for-flux-demo-app)
  - [Prepare Requirements](#prepare-the-requirements-for-the-demo-app-container)
    - [Upload/check Base Image](#upload-and-check-node-base-image)
    - [Sign Image](#sign-the-image-with-cosign)
    - [Build Image and push to Harbor](#build-the-demo-app-image-and-push-to-harbor)
    - [Kubernetes Docker Secret](#create-kubernetes-secret-for-harbor)
    - [Deploy demo-app by Argo](#deploy-the-demo-application-as-an-argo-application)

---


## Foreword

This repository contains a full demo workshop to start using the harbor container registry. At the end of the walkthrough, the given path should grant enough practical knowledge to implement harbor in a bigger and better environment. The current workshop has been created to run on kind.

[TOC](#table-of-contents)

## Clone the following repositories

https://github.com/xiloss/harbor-workshop.git
  
  it contains the current README.md file, and a set of scripts and helpers to deploy the workshop.

## Install Requirements

### When using Ubuntu

#### Setup sudo with no password or your current user (optional)

Skip the next command if you already have that ability or if you want to enter a password each time you open a new terminal session for the current user.

```bash
echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/$USER >/dev/null
```

[TOC](#table-of-contents)

#### Ensure Packages

Ensure you are up-to-date with all the required packages.
If you are using ubuntu as host operating system or virtual machine to run the idpbuilder workshop,
which is the base where the whole environment has been tested, ensure you have the following packages installed:

```bash
sudo apt update
sudo apt -y install openssh-server
sudo apt -y install curl
sudo apt -y install git
sudo apt -y install docker.io
```

[TOC](#table-of-contents)

#### Ensure docker installation

Check if the docker daemon is running correctly

```bash
systemctl status docker
```

Ensure the docker access is granted to the current usersudo usermod -aG docker $USER

```bash
sudo usermod -aG docker $USER
```

and reboot

```bash
sudo reboot
```

[TOC](#table-of-contents)

### Prerequisites

Ensure you have the following tools installed on your computer.

- kind: version 0.23.0 or later
- kubectl: version 1.27 or later
- helm: version 3.14.0 or later

### Installation

The whole setup will be operational executing the next steps.

#### Install Kind

To install kind you can use the next code snippet:

```bash
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind
```

or use the [helper](kind/get-kind.sh) in the kind folder

```bash
kind/get-kind.sh
```

and select a proper version.
For this tutorial the selected one is the 0.23.0, corresponding to kubernetes 1.30.

[TOC](#table-of-contents)

#### Install kubectl CLI

To install the kubectl latest version, run

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo mv ./kubectl /usr/local/bin
sudo chmod ugo+x /usr/local/bin/kubectl
kubectl version
```

As an optional step, add the completion executing the next snippets

```bash
source <(kubectl completion bash)
kubectl completion bash > $HOME/.kubectl.completion.bash.inc
printf "
# kubectl shell completion
source '$HOME/.kubectl.completion.bash.inc'
# setting up aliases
alias k='kubectl'
" >> $HOME/.bashrc
source $HOME/.bashrc
```

[TOC](#table-of-contents)

#### Install helm

Use the following commands to install a specific version of helm, the 3.14 for this case:

```bash
curl -fsSL https://get.helm.sh/helm-v3.14.0-linux-amd64.tar.gz -o helm.tar.gz
tar -zxvf helm.tar.gz linux-amd64/helm
sudo mv linux-amd64/helm /usr/local/bin/helm
rm -rf linux-amd64 helm.tar.gz
helm version
```

Additionally, add the completion, current commands are for the bash shell:

```bash
source <(helm completion bash)
helm completion bash > $HOME/.helm.completion.bash.inc
printf "
# helm shell completion
source '$HOME/.helm.completion.bash.inc'
" >> $HOME/.bashrc
source $HOME/.bashrc
```

[TOC](#table-of-contents)

#### Install argocd CLI (optional)

```bash
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd-linux-amd64
sudo mv argocd-linux-amd64 /usr/local/bin/argocd
argocd version
```

Additionally, add the completion, current snippet is for the bash shell

```bash
source <(argocd completion bash)
argocd completion bash > $HOME/.argocd.completion.bash.inc
printf "
# argocd shell completion
source '$HOME/.argocd.completion.bash.inc'
" >> $HOME/.bashrc
source $HOME/.bashrc
```

[TOC](#table-of-contents)

### Setup

#### Create kind cluster

Now it's time to create the kind cluster, using the proper configuration file available at [kind-config.yaml](kind/config/kind-config.yaml)
```bash
kind create cluster --name harbor-lab --config kind/config/kind-config.yaml
```

The current kind configuration file has a specific setting to ensure the harbor registry will be available from the host computer on port 5000.

[TOC](#table-of-contents)

#### Install ingress controller

To provide compatible ingress nginx controller, the kind specific integration is used:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.0/deploy/static/provider/kind/deploy.yaml
```

NOTE: in case of compatibility issues, check the kind repo for eventual alternative versions.

[TOC](#table-of-contents)

#### Install and configure cert-manager

To provide compatible cert-manager, the latest version is used:

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
```

NOTE: in case of compatibility issues, check the cert-manager repo for eventual alternative versions.

A ClusterIssuer using self-signed certificates is then created:

```bash
cat <<EOF | kubectl apply -f - 
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
EOF
```

[TOC](#table-of-contents)

#### Install Harbor

The helm chart values are provided at [harbor-values.yaml](harbor/harbor-values.yaml)

To install harbor using helm, execute the following command:

```bash
helm repo add harbor https://helm.goharbor.io
helm repo update
helm install harbor harbor/harbor -n harbor --create-namespace -f harbor/harbor-values.yaml
```

Now considering the given setup, where the harbor server will be available at `https://harbor.local` on the host computer, update the `/etc/hosts` file using the following command:

```bash
cat /etc/hosts | sed -r 's/(127\.0\.0\.1\ .*)/\1 harbor.local notary.harbor.local/g' | sudo tee /etc/hosts
```

[TOC](#table-of-contents)

##### Verifying the installation

Wait for the Harbor setup to complete, eventually checking with

```bash
kubectl wait --for=condition=Ready pods --all -n harbor --timeout=300s
```

Once everything is up and running, point the browser to `https://harbor.local`, and use `admin/Harbor12345` as credentials for initial access.

An important step when not using a specific trusted certificate or Harbor is to add its certificate to the `kind` node.
To add the harbor certificate once the installation completes, run the follwing command:

```bash
openssl s_client -connect harbor.local:443 -showcerts </dev/null 2>/dev/null | openssl x509 -outform PEM > harbor.crt
docker cp harbor.crt harbor-lab-control-plane:/usr/local/share/ca-certificates/harbor.crt
docker exec harbor-lab-control-plane update-ca-certificates
rm -f harbor.crt
```

and then restart the docker daemon, to ensure that the `kind` cluster is starting accepting and trusting the harbor certificate.

From the host machine, execute a 

```bash
docker login https://harbor.local
```

with the given credentials and ensure the login process succeeds.

[TOC](#table-of-contents)

##### NOTES

The current configuration can be modified altering the values on the harbor-values.yaml helm values.
The given setup for kind in the related configuration file provides persistence to the registry adding persistent volumes for both the harbor container registry and the trivy scanner.

[TOC](#table-of-contents)

### Pushing containers

Now that the host machine is connected to the Harbor server running inside the kubernetes kind cluster, it is possible to pull a container image locally and push it to the registry, checking that all the functionalities are available.

The next images will be used to show differences in security between the two versions:

```bash
docker pull nginx:alpine
docker tag nginx:alpine harbor.local/library/nginx:alpine
docker push harbor.local/library/nginx:alpine
docker pull nginx:latest
docker tag nginx:latest harbor.local/library/nginx:latest
docker push harbor.local/library/nginx:latest
```

After completing the previous steps, in the Harbor default project named `library` the two images will be ready and visible. 

[TOC](#table-of-contents)

### Running a local registry

#### Local registry setup

Now to test the abilities of replication with Harbor, on the host machine we will run a docker registry with the following command:

```bash
docker run -d \
  --restart=always \
  --name kind-registry \
  --network kind \
  -p 5000:5000 registry:2
```

Note that the `--network kind` arguments will be mandatory to have the Harbor deployment running in kind connecting to the local machine registry.

The local deployment can be test with the canonical:

```bash
docker login http://localhost:5000
```

executed on the host machine.

Then we can tag one of the previously downloaded images with a local registry reference, like the following example:

```bash
docker tag nginx:alpine localhost:5000/test/nginx:alpine
```

This will be useful to test the bidirectional abilities given by Harbor replication.

[TOC](#table-of-contents)

#### Configuring local registry in Harbor console

From the Harbor console, select the option "Registries" from the left bar, to add a new registry endpoint.
Follow the guidelines visible in [the given image](images/new-registry-endpoint.png)

After configuring the parameters correctly, the result should look like [this](images/new-registry-endpoint-ok.png)

Completing the configuration successfully will allow to setup replication rules.

[TOC](#table-of-contents)

#### Creating Replication rules

Now that we have a registry connected, we can create push or pull rules to demonstrate the abilities of Harbor to synchronize the images from and to one or more external sources.

To start the creation of the replication rules, select "Replications" from the left menu of the Harbor UI.
In the [given image](images/new-registry-replication-rules.png), the rules are already created and visible. Hit the "NEW REPLICATION RULE" button to create a rule.

[This](images/new-registry-replication-rules-push.png) is the example of a push rule

[This](images/new-registry-replication-rules-pull.png) is the example of a pull rule

For both cases, the rules are very simplified and they are matching `**` meaning all the images. This means that executing them manually as specified by default, they will be related to all the images present in the registry matching the configuration.

Once rules are effective, they can be tested executing them manually. The results will be best described by looking at the next images.

[Example pull rule execution summary](images/new-registry-replication-rules-pull-executions.png)

[Example pull rule execution result](images/new-registry-replication-rules-pull-executions-result.png)

[Example push rule execution summary](images/new-registry-replication-rules-push-executions.png)

[Example push rule execution result](images/new-registry-replication-rules-push-executions-result.png)

NOTE: playing with more rules and registries can be very productive, specially when considering a single Harbor UI as the main control panel for multitenancy offers and multiple CI/CD stages.

[TOC](#table-of-contents)

### Installing Dragonfly to start testing image distribution

For this step, only the installation of a single node kind dragonfly is integrated.
The scope of the current workshop is to give a proper integration of the dragonfly distribution system, this would be helpful in multiple nodes clusters, as so as in distirbuted container registries.
The current goal is to integrate the components.

First executing this command, the helm repositories are added:

```bash
helm repo add dragonfly https://dragonflyoss.github.io/helm-charts/
helm repo update
```

Once the inventories are updated, the next command will install dragonfly on the target kind cluster.

```bash
helm install dragonfly dragonfly/dragonfly \
  -n dragonfly-system \
  --create-namespace \
  --set dfdaemon.hostNetwork=true \
  --set dfdaemon.proxy.enabled=true \
  --set dfdaemon.proxy.defaultFilter="Expires&Signature&ns" \
  --set dfdaemon.proxy.registryMirror.enabled=true \
  --set dfdaemon.proxy.registryMirror.remote="http://kind-registry:5000" \
  --set dfdaemon.proxy.registryMirror.insecure=true
```

Once all the components are up, there is a service to patch for the dragonfly-manager, in fact by default all the provisioned service endpoints will be of type ClusterIP.
We need a NodePort to allow the connection from the Harbor running on the kind cluster.

```bash
kubectl patch svc dragonfly-manager \
  -n dragonfly-system \
  -p '{"spec": {"type": "NodePort"}}'
```

To provide additional connectivity to this cluster from the outside, updating the [kind-config.yaml](kind/config/kind-config.yaml)
with a section and port reserved for dragonfly, additional integrations from the outside will be possible. If that is the case, the previously patched service has to be updated with the reserved port specified in the [kind-config.yaml](kind/config/kind-config.yaml) file.

To connect the local Harbor installed server, the only IP to discover lil be the one of the service dragonfly-manager, previously changed to ClusterIP. The value can be discovered running

```bash
k get svc -n dragonfly-system dragonfly-manager -o jsonpath='{.spec.clusterIP}'
```

With that data, it is now possible to proceed configuring the Harbor server.

First select "Distributions" from the left menu, and click on the button "NEW INSTANCE", as shown [here](images/new-dragonfly-manager-instance.png).

Then on the pop-up window, complete the form with values similar to those used in the [image](images/new-dragonfly-manager-endpoint.png) and test the connection. The expected result is a successful green message.

Confirm to add the dragonfly instance to the Harbor configuration.
The final result should look like [this](images/new-dragonfly-manager-endpoint-ok.png).

NOTE: an experimental ingress controller configuration for exposing the dragonfly-manager service is available [here](kind/ingress-experimental/dragonfly-ingress.yaml). Use as replacement for the NodePort configuration, to research additional use case using the loadbalancer in case.

[TOC](#table-of-contents)

### Installing gitea for cluster CI/CD repositories

To provide the ability to work with a git server and functionalities, gitea will be installed.
First the helm repository is added:

```bash
helm repo add gitea-charts https://dl.gitea.com/charts/
helm repo update
```

Then the installation of gitea is performed with default values, specific version 10.6.0 that will work on kind and with kubernetes version 1.30.
To expose the service, the port 30003 previously specified in the [kind-config.yaml](kind/config/kind-config.yaml) file will be selected:

```bash
helm install gitea gitea-charts/gitea \
  --create-namespace \
  -n gitea \
  --version 10.6.0 \
  --set service.http.type=NodePort \
  --set service.http.nodePort=30003
  --set service.ssh.type=NodePort \
  --set service.ssh.nodePort=30022
```

Finally the local `/etc/hosts` file can be updated with the new entry to resolve gitea endpoints in a human readable way:

```bash
cat /etc/hosts | sed -r 's/(127\.0\.0\.1\ .*)/\1 gitea.kind.local/g' | sudo tee /etc/hosts
```

With these changes we should now be able to reach gitea from the host to the next endpoints:

|host|port|service|
|:-|:-|:-|
|gitea.local|30003|http/UI|
|gitea.local|30022|http/UI|

[TOC](#table-of-contents)

### Installing ArgoCD on kind

To install ArgoCD we will use the manifest file approach, and for this case we will use the laest stable ArgoCD release from the official Argo Project repository:

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

This installs all necessary components:

- argocd-server: UI/API server
- argocd-repo-server: Git repository interactions
- argocd-application-controller: syncs desired state
- argocd-dex-server: optional authentication

As usual, check that all the pods in the `argcd` namespace are in a "Running" state to test the installation.

There is an `argocd-server` service in the installation, that is by default create as type "ClusterIP". To access it from inside the kind cluster and to map it as an external available service without adding an ingress resource, it is necessary to move it to a type "NodePort". Eventually the [kind-config.yaml](kind/config/kind-config.yaml) file has a dedicated port exposed for it uncommented, it can be used for reaching the argocd UI without the need for a port-forward configuration.

The ingress file [argocd-ingress.yaml](kind/ingress-experimental/argocd-ingress.yaml) can be used to map the UI using the given configuration. For that case, a domain name mapped `argocd.kind.local` will be available and it has to be mapped in the `/etc/hosts` file to be effective.
The next commands summarize the configuration above:

```bash
kubectl apply -f ingress-experimental/argocd-ingress.yaml
cat /etc/hosts | sed -r 's/(127\.0\.0\.1\ .*)/\1 argocd.kind.local/g' | sudo tee /etc/hosts
```

Once the argo endpoint is responding and reachable, to retrieve the initial password execute:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```

As the argo CLI has been previously installed, the next command should work to login to the cluster from the command line:

```bash
argocd login argocd.kind.local --insecure --grpc-web
```

The credentials work for both the UI and the CLI.

The argo UI should now be reachable at `https://argocd.kind.local`

[TOC](#table-of-contents)

#### Argo gitea setup

To start using argocd with gitea first we need to create an organization, a user, a team, and then the git repository.
The first thing to do is to get a personal access token with the rights to create an organization and a repository in gitea.
We are going to use the REST approach, but the same result can be achieved simply using the gitea UI.

NOTE: since this process is the same used for the fluxcd gitea user and related flux repository and organization, the images will show the names for that case. Be sure to follow the instruction consistently and use the alternate names for argocd.
The process for the gitea_admin personal access token is still the same, and can be followed only once.

First [login](images/gitea-ui-login.png) to gitea UI at the endpoint.

1. Go to [Settings](images/gitea-ui-admin-settings.png)
2. [fill](images/gitea-ui-admin-generate-token.png) in the token name in the form
3. [provide](images/gitea-ui-admin-generate-token-permissions.png) some basic settings for the token permissions
4. write down the [newly generated token](images/gitea-ui-admin-generate-token-success.png)


```bash
export GITEA_TOKEN="2074be8e2dfe544f66226445da84f474b1f276e1"
export GITEA_URL="http://gitea.kind.local:30003"
export GITEA_API="$GITEA_URL/api/v1"
```

Verify that the endpoint and ports are effectively matching your local configuration.

NOTE: if the [gitea ingress file](kind/ingress-experimental/gitea-ingress.yaml) has been previously applied, and the `/etc/hosts` file has been updated to point ot gitea.kind.local for the gitea REST endpoint, the GITEA_URL can be set with value `http://gitea.kind.local`

Then execute the organization creation via REST:

```bash
curl -X POST "$GITEA_API/orgs" \
  -H "Authorization: token $GITEA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "argo-org",
    "description": "Organization for ArgoCD repos",
    "visibility": "public"
}'
```

The response should be a positive JSON output, and the result in the UI should look similar to [this](images/gitea-ui-org-created.png).

Now running the next command, the repository inside the newly created organization will be set:

```bash
curl -X POST "$GITEA_API/orgs/argo-org/repos" \
  -H "Authorization: token $GITEA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "argo-config",
    "description": "GitOps configuration for ArgoCD",
    "private": false,
    "auto_init": true
}'
```

The output of the CLI shoudl be a consistent JSON description of the attributes of the newly created repository, called `argo-config`.

Clicking on the argo-org in the UI, the summary should look similar to [this](images/gitea-ui-repo-created.png).

We have successfully set the argo repository in `http://gitea.kind.local:30003/argo-org/argo-config.git`

Let's create the `argocd` user now:

```bash
curl -X POST "$GITEA_API/admin/users" \
  -H "Content-Type: application/json" \
  -H "Authorization: token $GITEA_TOKEN" \
  -d '{
        "email": "argocd@gitea.local",
        "username": "argocd",
        "password": "changeme",
        "must_change_password": false,
        "send_notify": false
      }'
```

Add a team to the organization

```bash
curl -X POST "$GITEA_API/orgs/argo-org/teams" \
  -H "Authorization: token $GITEA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "maintainers",
    "description": "Argo maintainers",
    "permission": "write",
    "units": ["repo.code", "repo.issues", "repo.pulls"]
}'
```

Check the new team id, mine for this case is `5`

```bash
curl -X GET "$GITEA_API/orgs/argo-org/teams" -H "Authorization: token $GITEA_TOKEN"
```

and add the `argocd` user to the `argo-org` organization as a member of the `maintainers` team

```bash
curl -X PUT "$GITEA_API/teams/5/members/argocd" \
  -H "Authorization: token $GITEA_TOKEN" \
  -H "Content-Type: application/json"
```

Now add the repository to the maintainers team

```bash
curl -X PUT "$GITEA_API/teams/5/repos/argo-org/argo-config" \
  -H "Authorization: token $GITEA_TOKEN" \
  -H "Content-Type: application/json"
```

Now we can create a personal access token, named `argocd-access-token` for the user `argocd`, authenticating to the gitea REST endpoint, and use this credentials pair for the argocd operations.

```bash
curl -X POST "$GITEA_API/users/argocd/tokens" \
  -u argocd:changeme \
  -H "Content-Type: application/json" \
  -d '{
    "name":"argocd-access-token",
    "scopes":["all"]
  }'
```
The token for this case is `c35cbea92b133fe1218f562b0ce8845f74379bd5`.

Finally we can setup argo using the CLI to use the repository, executing the next command:

```bash
argocd repo add http://gitea-http.gitea.svc.cluster.local:3000/argo-org/argo-config.git \
  --username argocd \
  --password c35cbea92b133fe1218f562b0ce8845f74379bd5 \
  --insecure-skip-server-verification \
  --name argo-config
```

For the previous command to succeed, ensure you are still connected with a valid session to you argocd endpoint. You should have run previously the command

```bash
argocd login argocd.kind.local --insecure --grpc-web
```

Eventually verify the current `argocd` CLI context, running

```bash
argocd context
```

or also

```bash
argocd account get-user-info
```

If everything is fine, the repository should be added, and the result from the argo UI should be as [this](images/argo-ui-repo.png).

[TOC](#table-of-contents)

### Installing fluxcd2 on kind

To install the fluxcd 2 CLI on the host machine, it's a single command; execute:

```bash
curl -sSL https://fluxcd.io/install.sh | sudo bash
flux --version
```

The result should be the output of the installed version, for the current set it's `flux version 2.6.1`

[TOC](#table-of-contents)

#### flux gitea setup

First [login](images/gitea-ui-login.png) to gitea UI at the endpoint.

1. Go to [Settings](images/gitea-ui-admin-settings.png)
2. [fill](images/gitea-ui-admin-generate-token.png) in the token name in the form
3. [provide](images/gitea-ui-admin-generate-token-permissions.png) some basic settings for the token permissions
4. write down the [newly generated token](images/gitea-ui-admin-generate-token-success.png)


```bash
export GITEA_TOKEN="2074be8e2dfe544f66226445da84f474b1f276e1"
export GITEA_URL="http://gitea.kind.local:30003"
export GITEA_API="$GITEA_URL/api/v1"
```

Verify that the endpoint and ports are effectively matching your local configuration.

NOTE: if the [gitea ingress file](kind/ingress-experimental/gitea-ingress.yaml) has been previously applied, and the `/etc/hosts` file has been updated to point ot gitea.kind.local for the gitea REST endpoint, the GITEA_URL can be set with value `http://gitea.kind.local`

Then execute the organization creation via REST:

```bash
curl -X POST "$GITEA_API/orgs" \
  -H "Authorization: token $GITEA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "flux-org",
    "description": "Organization for FluxCD repos",
    "visibility": "public"
}'
```

The response should be a positive JSON output, and the result in the UI should look similar to [this](images/gitea-ui-org-created.png).

Now running the next command, the repository inside the newly created organization will be set:

```bash
curl -X POST "$GITEA_API/orgs/flux-org/repos" \
  -H "Authorization: token $GITEA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "flux-config",
    "description": "GitOps configuration for FluxCD",
    "private": false,
    "auto_init": true
}'
```

The output of the CLI should be a consistent JSON description of the attributes of the newly created repository, called `flux-config`.

Clicking on the `flux-org` in the UI, the summary should look similar to [this](images/gitea-ui-repo-created.png).

We have successfully set the flux repository in `http://gitea.kind.local:30003/flux-org/flux-config.git`

Let's create the `fluxcd` user now:

```bash
curl -X POST "$GITEA_API/admin/users" \
  -H "Content-Type: application/json" \
  -H "Authorization: token $GITEA_TOKEN" \
  -d '{
        "email": "fluxcd@gitea.local",
        "username": "fluxcd",
        "password": "changeme",
        "must_change_password": false,
        "send_notify": false
      }'
```

Add a team to the organization

```bash
curl -X POST "$GITEA_API/orgs/flux-org/teams" \
  -H "Authorization: token $GITEA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "maintainers",
    "description": "Flux maintainers",
    "permission": "write",
    "units": ["repo.code", "repo.issues", "repo.pulls"]
}'
```

Check the new team id, mine for this case is `3`

```bash
curl -X GET "$GITEA_API/orgs/flux-org/teams" -H "Authorization: token $GITEA_TOKEN"
```

and add the `fluxcd` user to the `flux-org` organization as a member of the `maintainers` team

```bash
curl -X PUT "$GITEA_API/teams/3/members/fluxcd" \
  -H "Authorization: token $GITEA_TOKEN" \
  -H "Content-Type: application/json"

```

Now add the repository to the maintainers team

```bash
curl -X PUT "$GITEA_API/teams/3/repos/flux-org/flux-config" \
  -H "Authorization: token $GITEA_TOKEN" \
  -H "Content-Type: application/json"
```

Now we can create a personal access token, named `fluxcd-access-token` for the user `fluxcd`, authenticating to the gitea REST endpoint, and use this credentials pair to bootstrap flux.

```bash
curl -X POST "$GITEA_API/users/fluxcd/tokens" \
  -u fluxcd:changeme \
  -H "Content-Type: application/json" \
  -d '{
    "name":"fluxcd-access-token",
    "scopes":["all"]
  }'
```
The token for this case is `7dd93d62e366900529dcdb4dc85fe378ebd016d3`.
Finally we can setup flux to access the repository, executing the next command:

```bash
flux bootstrap git \
  --url=http://gitea.kind.local:30003/flux-org/flux-config.git \
  --username=fluxcd \
  --password=7dd93d62e366900529dcdb4dc85fe378ebd016d3 \
  --branch=main \
  --token-auth \
  --path=clusters/dev \
  --allow-insecure-http=true \
  --insecure-skip-tls-verify
```

and since the command line on the host system is pointing to http://gitea.kind.local:30003, but the flux controller from inside the cluster is calling the internal service endpoint, we have to patch the repository as soon as it is created by the previous flux bootstrap command.
To achieve that, we run the next command:

```bash
kubectl -n flux-system \
  patch gitrepository flux-system \
  --type=json \
  -p='[{"op":"replace","path":"/spec/url","value":"http://gitea-http.gitea.svc.cluster.local:3000/flux-org/flux-config.git"}]'
```

Once the path is successfully committed, the previous `flux bootstrap` command should succeed.

[TOC](#table-of-contents)

## The Experiment Demo

The next steps are intended to be the demonstration of various CI/CD features available with the given bundle of tools.

Tools that will be used:

- **Docker CLI**, for building and pushing images
- **Harbor**, running in kind, to host/scan/sign/replicating container images
- **FluxCD**, handling image update automation
- **ArgoCD**, handling deployment from a Git repo hosted on internal Gitea
- **Gitea**, hosting the git service for the current stack

### Create Harbor Users

To test some feature of Harbor and CI/CD integration, three users will be created, from inside the Harbor UI.
The steps are best described in the next images:

- Create a new user
  [Harbor New User](images/harbor-new-user.png)
- Check the default Harbor password security policy
  [Harbor Password Requirements](images/harbor-new-user-password-req.png)
- Confirm creation of a new user
  [Harbor New User Creation](images/harbor-new-user-ok.png)
- Recap of users created
  [Harbor New Users Summary](images/harbor-all-users.png)

[TOC](#table-of-contents)

### Create New Repository for flux demo app

Now the gitea service will be used to create a flux demo application, with configuration to handle the image update automation.
The repository [`demo-app`](flux/demo-app/) will have the following tree structure:

```css
demo-app/
├── Dockerfile
├── app/
│   └── main.js
└── clusters/
    └── dev/
        └── deployment.yaml
```

To proceed to the repository creation, using the gitea UI, [create a new repository](images/gitea-flux-repo-create.png) in the `flux-org` organization, and call it [`demo-app`](images/gitea-flux-repo-demo-app.png).

Write down the details from the report, as from [this image](images/gitea-flux-repo-demo-app-add.png)

Open a terminal and go to the local folder containing the sources for the [`demo-app`](flux/demo-app/)

Ensure you have the minimal required configuration for the git CLI to work with no exceptions:

```bash
git config --local user.email fluxcd@cluster.local
git config --local user.name "Fluxcd cluster.local"
```

Then run the next commands:

```bash
git init
git checkout -b main
git add .
git commit -m "demo-app"
git remote add origin http://gitea.kind.local/flux-org/demo-app.git
git push -u origin main
```

Now the content of the repository should be visible in the Gitea UI after refreshing the page.

NOTE: in case of permission errors, while pushing to the remote registry, it could be necessary to add the team of the maintainers to the repository collaborators.
Check [this image](images/gitea-ui-add-maintainers-team.png) as reference, and add the team `maintainers` to the current configuration.

[TOC](#table-of-contents)

### Prepare the requirements for the demo-app container

#### Upload and check node base image

Since we are going to use a node image to build the `demo-app` application, which is a nodejs one, we are going to put the base container image in our Harbor registry, to ensure we are using a consistent source, and also to be aware of the security issues on the base image.

First in the Harbor UI we are going to setup a [new project](images/harbor-new-project.png) called [`base-images`](images/harbor-project-base-images.png).

Then we login to harbor from the host computer using the docker CLI:

```bash
docker login https://harbor.local
```

Use the credentials for the admin user, this is a generic public registry. They should be cached in the local configuration, after the first login.

Now pull/push the node image we are going to use later to build the demo application:

```bash
docker pull node:18-alpine
docker tag node:18-alpine harbor.local/base-images/node:18-alpine
docker push harbor.local/base-images/node:18-alpine
```

Once the process is completed, we can manually run the trivy scan and SBOM analysis from the Harbor UI.
The result of the triggering of the two operations "SCAN" and "GENERATE SBOM" is visible [here](images/harbor-node-image-scan.png) as a sample.

[TOC](#table-of-contents)

#### Sign the image with cosign

Install the `cosign` tool and proceed to create certificates to sign the image and ensure the signature in Harbor.

```bash
COSIGN_VERSION=$(curl -s https://api.github.com/repos/sigstore/cosign/releases/latest | jq -r .tag_name)
curl -Lo cosign https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-linux-amd64
chmod +x cosign
sudo mv cosign /usr/local/bin/
cosign version
```

After running the command, the reposnse should be a banner with details about cosign version.

Now let's generate a `cosign` keypair:

```bash
cosign generate-key-pair
```

Enter to confirm with empty passphrase.

And now to sign the image in Harbor:

```bash
COSIGN_PASSWORD="" cosign sign --key cosign.key harbor.local/base-images/node:18-alpine --allow-insecure-registry -y
```

At the end of the process, refreshing the Harbor UI page for the given image, it ill show the green checkmark on the "Signed" attribute for the image, as in the [example image](images/harbor-node-image-signed.png).


NOTE: the image signing process proposed here is provided as example and it's not really following the correct TLS and SSL guidelines for signing, in fact the insecure option required to complete the steps is used to avoid all the security checks granted by a consistent Authority credentials set.
It is recommended to investigate deeper the sections related to image signing, Harbor, notary v1 and v2 docker integration, deprecations.

[TOC](#table-of-contents)

#### Build the demo-app image and push to Harbor

After the signing process, we are now ready to build our container image from the proposed [`Dockerfile`](flux/demo-app/Dockerfile).
Due to the lack of local pipeline integrations, we will run the build process manually, while the flux repository will ensure the image versioning in our CI/CD.

To proceed to create the artifact, and upload it to Harbor:

```bash
cd flux/demo-app
docker build -t harbor.local/dev/demo-app:0.0.1 .
docker push harbor.local/dev/demo-app:0.0.1
```

Note that the push refers to Harbor specific project library `dev`.

We can also sign the image:

```bash
COSIGN_PASSWORD="" cosign sign --key cosign.key harbor.local/dev/demo-app:0.0.1 --allow-insecure-registry -y
```

and check the result for the trivy scan and the signed result.

[TOC](#table-of-contents)

#### Create kubernetes secret for harbor

In order for the demo-app deployment to be able to pull the image from the Harbor server, we need to create a kubernetes secret, running the next command:

```bash
kubectl create secret docker-registry harbor-creds \
  --namespace=default \
  --docker-server=harbor.local \
  --docker-username=admin \
  --docker-password=Harbor12345 \
  --docker-email=dev@local.dev
```

This will ensure that the harbor-creds secret will be successfully used to authenticate with harbor and pull the image.

[TOC](#table-of-contents)

#### Deploy the demo application as an argo application

To use the container and the [`deployment.yaml`](flux/demo-app/clusters/dev/deployment.yaml) file effectively, we will use ArgoCD, creating an application from the file [demo-app.yaml](argo/demo-app.yaml).
Considering the whole previous setup, the image should be now being pulled from Harbor.
To create the Argo Application run the command:

```bash
kubectl apply -f argo/demo-app.yaml
```

Check the Argo UI to ensure that the application is loaded and available. Check the application status, the deployment of the container and the related image from harbor should be up and running inside the kind cluster.

[TOC](#table-of-contents)
