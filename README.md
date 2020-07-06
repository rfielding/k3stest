# k3s test

The goal is to install a trivial k3s app, along with the dashboard, so that you can see deployments wiring into the ingress and mounting applications to forward to.

## Prerequisites:

- Install Docker if you have not already
- Install k3s:  https://rancher.com/docs/k3s/latest/en/quick-start/
- Install helm if you have not already

> I know that this lacks detail at the moment.  I do not have a clean machine from which to document exactly what I did right now.

Once k3s is installed, you have a trivial Kubernetes installation on your local machine, that from kubectl resembles a realistic setup.  Note that Kubernetes tooling is always kind of wobbly, as versions move up quickly, with breakage as this happens.


## Intro

Just about every Kubernetes tutorial you will read will leave you stuck at a point where they made an assumption about your setup.  And the configs are so verbose, that you just kind of have to copy things around without asking why for a while.  Some required minikube, others k3s, etc.  The one thing in Kubernetes that isn't trivial is the one thing that should probably be most trivial: spawning a reverse proxy on a port available from your shell network (ie: on OSX, you can't just talk to IPs in your docker network).  These tutorials also blindly import a bunch of yaml files with little to no explanation of what it's for; making it less than a tutorial.

So, this is going to document a trivial `k3s` setup, adapted from a kubernetes.io scenario.

- Setup a Redis cluster
- Setup a trivial front-end app
- Setup the load balancer to get into the app, especially on OSX where it is impossible to hit the actual IP directly.

We have some yaml files:

```
-rw-r--r--   1 rfielding  staff    587 Jul  6 16:31 redis-master-deployment.yaml
-rw-r--r--   1 rfielding  staff    233 Jul  6 16:31 redis-master-service.yaml
-rw-r--r--   1 rfielding  staff   1135 Jul  6 16:31 redis-slave-deployment.yaml
-rw-r--r--   1 rfielding  staff    210 Jul  6 16:31 redis-slave-service.yaml
```

Front-end:

```
-rw-r--r--   1 rfielding  staff   1108 Jul  6 16:31 frontend-deployment.yaml
-rw-r--r--   1 rfielding  staff    439 Jul  6 16:31 frontend-service.yaml
```

Ingress related:

```
-rw-r--r--   1 rfielding  staff    330 Jul  6 16:31 ingress.yaml
-rw-r--r--   1 rfielding  staff   1106 Jul  6 16:31 traefik.yaml
```

## Redis setup

This is a verbose way of creating a master redis, implying scale of 1, to start a cluster.  This is the basic service, which is quite redundant, so you are stuck cargo-culting around anything that works.  Note that port is specified here.

> redis-master-service.yaml

```yaml
apiVersion: v1
kind: Service
metadata:
  name: redis-master
  labels:
    app: redis
    role: master
    tier: backend
spec:
  ports:
  - port: 6379
    targetPort: 6379
  selector:
    app: redis
    role: master
    tier: backend
```

Did I mention that Kubernetes is very redundant?  Note that it is the DEPLOYMENT that mentions the docker image.
The port also has to be specified here, in case there needs to be a port re-mapping of the container.
What does make sense is the number of replicas, and the name of redis-master.

> redis-master-deployment.yaml

```yaml

apiVersion: apps/v1 # for versions before 1.9.0 use apps/v1beta2
kind: Deployment
metadata:
  name: redis-master
  labels:
    app: redis
spec:
  selector:
    matchLabels:
      app: redis
      role: master
      tier: backend
  replicas: 1
  template:
    metadata:
      labels:
        app: redis
        role: master
        tier: backend
    spec:
      containers:
      - name: master
        image: k8s.gcr.io/redis:e2e  # or just image: redis
        resources:
          requests:
            cpu: 100m
            memory: 100Mi
        ports:
        - containerPort: 6379
```

And for the Redis slaves, where the service is nearly identical except for metadata name:

> redis-slave-service.yaml

```yaml
apiVersion: v1
kind: Service
metadata:
  name: redis-slave
  labels:
    app: redis
    role: slave
    tier: backend
spec:
  ports:
  - port: 6379
  selector:
    app: redis
    role: slave
    tier: backend
```

And this is how how Redis slave is deployed.  Did I mention redundancy?

```yaml
apiVersion: apps/v1 # for versions before 1.9.0 use apps/v1beta2
kind: Deployment
metadata:
  name: redis-slave
  labels:
    app: redis
spec:
  selector:
    matchLabels:
      app: redis
      role: slave
      tier: backend
  replicas: 2
  template:
    metadata:
      labels:
        app: redis
        role: slave
        tier: backend
    spec:
      containers:
      - name: slave
        image: gcr.io/google_samples/gb-redisslave:v3
        resources:
          requests:
            cpu: 100m
            memory: 100Mi
        env:
        - name: GET_HOSTS_FROM
          value: dns
        ports:
        - containerPort: 6379

```

## Frontend

The Frontend is a trivial web app (which should probably be built from source in this repo)

> frontend-service.yaml

```yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend
  labels:
    app: guestbook
    tier: frontend
spec:
  type: NodePort 
  ports:
  - port: 80
  selector:
    app: guestbook
    tier: frontend

```

And the deployment of frontend:

> frontend-deployment.yaml

```yaml
apiVersion: apps/v1 # for versions before 1.9.0 use apps/v1beta2
kind: Deployment
metadata:
  name: frontend
  labels:
    app: guestbook
spec:
  selector:
    matchLabels:
      app: guestbook
      tier: frontend
  replicas: 3
  template:
    metadata:
      labels:
        app: guestbook
        tier: frontend
    spec:
      containers:
      - name: php-redis
        image: gcr.io/google-samples/gb-frontend:v4
        resources:
          requests:
            cpu: 100m
            memory: 100Mi
        env:
        - name: GET_HOSTS_FROM
          value: dns
        ports:
        - containerPort: 80

```

## Ingress

Ingress is one of the more tricky parts of Kubernetes.  If you are on Linux, you may be taking shortcuts that you cannot take on OSX.  On OSX, your only entry point is in through the `k3d` container.

I had to modify the default traefik.yaml by extracting it like: `kubectl -n kube-system get -o cm traefik` and modify it like this:

> traefik.yaml

```yaml
apiVersion: v1
data:
  traefik.toml: |
    # traefik.toml
...
    [api]
      dashboard = true
...
metadata:
  creationTimestamp: "2020-07-06T16:40:15Z"
  labels:
    app: traefik
    chart: traefik-1.81.0
    heritage: Helm
    release: traefik
  name: traefik
  namespace: kube-system
#  resourceVersion: "7495"
  selfLink: /api/v1/namespaces/kube-system/configmaps/traefik
#  uid: 91f80c9e-8477-44e3-a2c0-51b0d39db1c4
```

All this just to do something that should be like: `traefik.api.dashboard = true`, and bounce traefik.

And then there is the actual mappings, done with an nginx server:

```yaml
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: nginx
  annotations:
    ingress.kubernetes.io/ssl-redirect: "false"
#    ingress.kubernetes.io/rewrite-target: /$1
spec:
  rules:
  - http:
      paths:
      #- path: /front
      - path: /
        backend:
          serviceName: frontend
          servicePort: 80
```

What is important is that all port 80 traffic hitting the ingress container will be sent to `frontend:80`.
This is only PART of getting this to work, because the build script that sets it all up:

```bash
#!/bin/bash

k3d delete all

k3d create --port 80:80 
sleep 30
export KUBECONFIG="$(k3d get-kubeconfig --name='k3s-default')"
sleep 60

kubectl apply -f redis-master-deployment.yaml	
kubectl apply -f redis-master-service.yaml	
kubectl apply -f redis-slave-deployment.yaml	
kubectl apply -f redis-slave-service.yaml
kubectl apply -f frontend-deployment.yaml	
kubectl apply -f frontend-service.yaml	
kubectl apply -f ingress.yaml
kubectl apply -f traefik.yaml
sleep 10
kubectl -n kube-system scale deploy traefik --replicas 0
kubectl -n kube-system scale deploy traefik --replicas 1
sleep 20
kubectl -n kube-system port-forward deployment/traefik 8080 &
``` 

The sleeps are in there because as a distributed system, where readiness probes are being used, there are race conditions on getting everything up and running.  The main highlights:

- The ingress setup is
  - traefik.yaml - to just edit to get the dashboard running at http://localhost:8080
  - ingress.yaml - to setup the web site endpoint at http://localhost:80
- The KUBECONFIG file has the admin user and password, which can be used to check https://localhost:6443 to connect to Kubernetes control, like the kubectl command does.

So, if you bring up your browser to these URLS, you are working:

- http://localhost:80 - a trivial app that uses Redis and some static assets
- http://localhost:8080 - a traefik dashboard, that if you modify `ingress.yaml` via: `kubectl apply -f ingress.yaml` will hot-reload to show the current state of ingress.

Other commands:

```
kubectl -n kube-system get all
```

