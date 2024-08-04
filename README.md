# Docker CI Template

This template will automatically build, release and push docker images for you as soon as a new base image is available.

Simply place a `Dockerfile` at the root of the repo e.g.:

```
FROM debian:bookworm-20240211

RUN apt-get update && apt-get install -y \
    fortune \
    cowsay \
    && rm -rf /var/lib/apt/lists/*
RUN echo '/usr/games/fortune | /usr/games/cowsay && echo -e "\n"' >> /etc/bash.bashrc
```

Is important **not** to use a tag like `latest`, `stable` or any other tag that is not regular updated. For debian there are for example images with a date inside the tag.

The workflows will automatically build and release a new debian images with a `cowsay` message of the day under the following name: `{DOCKER_HUB_USERNAME}/{REPO_NAME}:{BASE_IMAGE_TAG}` e.g.: `mietzen/debian-cowsay:bookworm-20240211` (The latest image also gets the `latest` tag)

**Cowsay Example:** [https://github.com/mietzen/debian-cowsay](https://github.com/mietzen/debian-cowsay)

The workflow will build all platform listed in [`platforms.json`](.github/platforms.json) and also push them as a multi-arch image.

## Usage

Click on `Use this template`:

![](https://github.com/mietzen/docker-ci-template/blob/8cf107cd387f7301ac6625cf324416965b362974/use-template.png?raw=true)

And follow the preparation steps.

## Preparation

### Github Token App

For the workflow to run you need to create a GitHub-App to generate tokens, follow:

[https://github.com/actions/create-github-app-token](https://github.com/actions/create-github-app-token?tab=readme-ov-file#usage)

If you follow the instructions above you should have your App listed under `Settings -> GitHub Apps`:

![](https://github.com/mietzen/docker-ci-template/blob/313cb3c73a4ce2a43397a3a749bfcc238c967367/github-app.png?raw=true)

### Repository config

You need to activate `auto-merge` under `Settings -> General -> Pull Requests`:

![](https://github.com/mietzen/docker-ci-template/blob/313cb3c73a4ce2a43397a3a749bfcc238c967367/auto-merge.png?raw=true)

and setup the branch protection for `main` under `Settings -> Branch -> Add branch protection rule`, for `Branch name pattern` type in `main`:

Then apply the following settings:

![](https://github.com/mietzen/docker-ci-template/blob/313cb3c73a4ce2a43397a3a749bfcc238c967367/branch-protection.png?raw=true)

**The status check `Check-Build` is only available after the `docker-image.yml` ran at least one time. You can trigger the workflow by simply opening a Pull-Request e.g. to add your `Dockerfile`.**

#### Secrets

You need to add the following secrets as repository secrets in Actions:

- `APP_ID`
- `APP_PRIVATE_KEY`
- `DOCKER_HUB_DEPLOY_KEY`

![](https://github.com/mietzen/docker-ci-template/blob/313cb3c73a4ce2a43397a3a749bfcc238c967367/action-secrets.png?raw=true)

**and** to Dependabot:

- `APP_ID`
- `APP_PRIVATE_KEY`

![](https://github.com/mietzen/docker-ci-template/blob/313cb3c73a4ce2a43397a3a749bfcc238c967367/dependabot-secrets.png?raw=true)

[Optional] Add your DockerHub username and/or the docker image name under variables:

- `DOCKER_HUB_USERNAME`
- `IMAGE_NAME`

![](https://github.com/mietzen/docker-ci-template/blob/313cb3c73a4ce2a43397a3a749bfcc238c967367/actions-vars.png?raw=true)
