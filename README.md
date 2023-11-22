# Italic Deploy

A collection of deployment scripts

## Installation

```
composer config repositories.repo-name vcs https://github.com/germain-italic/italic-deploy
composer require germain-italic/italic-deploy:^1.0.0
```



## Run
```
bash vendor/bin/sync_uploads.sh
bash vendor/bin/sync_db.sh
bash vendor/bin/deploy.sh
```



## Shortcuts

After requiring `germain-italic/italic-deploy`, add the following script to your project's `composer.json`:

```json
"scripts": {
    "deploy": "bash vendor/bin/deploy.sh",
    "sync_db": "bash vendor/bin/sync_db.sh",
    "sync_db": "bash vendor/bin/sync_db.sh"
}
```

Then you can tasks like this:

```
composer deploy
composer sync_db
composer sync_db
```