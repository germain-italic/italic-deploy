# Italic Deploy

A collection of interactive deployment scripts.



## Installation

### Pre-requisite: Composer

If you already use Composer in your project, skip this step. Otherwise, run:

```
composer init
```

Leave the default values, until you reach these questions, answer `no` or `n`:

```
Would you like to define your dependencies (require) interactively [yes]? no
Would you like to define your dev dependencies (require-dev) interactively [yes]? no
Add PSR-4 autoload mapping? Maps namespace "Germain\WordpressStoreOrange" to the entered relative path. [src/, n to skip]: n
```

Last question, answer `yes`:

```
Do you confirm generation [yes]? yes
```

Composer is now initialized in your project.

---

### Next steps

The package is not published on Packagist, you must define the repository:

```
composer config repositories.repo-name vcs https://github.com/germain-italic/italic-deploy
```

If you want to use the **Stable version**:
```
composer require germain-italic/italic-deploy:^1.0.0
```

Or, if you want to use the **Development version**:
```
composer require germain-italic/italic-deploy:"dev-master"
```



## Update

```
composer update germain-italic/italic-deploy
```


## Run
```
bash vendor/bin/sync_uploads.sh
bash vendor/bin/sync_db.sh
bash vendor/bin/deploy.sh
```