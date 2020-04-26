Source of <https://www.arnavion.dev/>


# Pre-requisites

```sh
zypper in --no-recommends pandoc sassc
```


# Build

```sh
./build.sh
```


# Deploy locally

```sh
python3 -m http.server 8080 -d out
```


# Deploy to Azure

```sh
./build.sh publish
```
