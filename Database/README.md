# Introduction

Databases are organized, digital repositories for storing, managing, and retrieving structured or unstructured data. They are essential for managing large, complex, and evolving data sets efficiently.

## Redis

[Redis](https://redis.io/open-source/) is an open-source, in-memory data structure store.

Steps to install Redis:
1. Specify LLVM and Redis version via environment variables
2. run the `redis.sh`

```shell
cd Database/

# switch to root first
sudo su

# LLVM and Redis version, e.g.
export LLVM_ver='21'
export redis_ver='8.8.0'

# install redis
./scripts/redis.sh
```

> Last Updated: 2026-06-20
