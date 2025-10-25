name: Build and Push Docker Image

on:
  push:
    branches: [ main ]
    paths-ignore:
      - '**/*.md'
      - 'docs/**'
  pull_request:
    paths-ignore:
      - '**/*.md'
      - 'docs/**'
  workflow_dispatch:

jobs:
  build-amd64:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up QEMU (safety for cross-builds)
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      # PR에서는 시크릿 접근 불가 → 로그인/푸시 조건부
      - name: Log in to Docker Hub
        if: ${{ github.event_name != 'pull_request' && secrets.DOCKERHUB_USERNAME && secrets.DOCKERHUB_TOKEN }}
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      - name: Build image (PR=build only, main=push)
        uses: docker/build-push-action@v6
        with:
          context: .
          platforms: linux/amd64
          push: ${{ github.event_name != 'pull_request' }}
          # PR에서는 시크릿을 못 읽을 수 있으므로 로컬 태그로 fallback
          tags: ${{ github.event_name != 'pull_request' && secrets.DOCKERHUB_USERNAME != '' && secrets.DOCKERHUB_TOKEN != '' && format('{0}/om1:latest-amd64', secrets.DOCKERHUB_USERNAME) || 'local/om1:ci-amd64' }}

  build-arm64:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to Docker Hub
        if: ${{ github.event_name != 'pull_request' && secrets.DOCKERHUB_USERNAME && secrets.DOCKERHUB_TOKEN }}
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      - name: Build image (PR=build only, main=push)
        uses: docker/build-push-action@v6
        with:
          context: .
          platforms: linux/arm64
          push: ${{ github.event_name != 'pull_request' }}
          tags: ${{ github.event_name != 'pull_request' && secrets.DOCKERHUB_USERNAME != '' && secrets.DOCKERHUB_TOKEN != '' && format('{0}/om1:latest-arm64', secrets.DOCKERHUB_USERNAME) || 'local/om1:ci-arm64' }}

  create-manifest:
    needs: [build-amd64, build-arm64]
    if: ${{ github.event_name != 'pull_request' }} # PR일 때는 스킵
    runs-on: ubuntu-latest
    steps:
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to Docker Hub
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      - name: Create and push manifest
        run: |
          docker buildx imagetools create \
            -t ${{ secrets.DOCKERHUB_USERNAME }}/om1:latest \
            ${{ secrets.DOCKERHUB_USERNAME }}/om1:latest-amd64 \
            ${{ secrets.DOCKERHUB_USERNAME }}/om1:latest-arm64
