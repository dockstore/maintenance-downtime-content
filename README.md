# maintenance-downtime-content

This repository houses the "down page" content for the Dockstore service.  On push, the CI job copies the contents of the `/content` directory to a branch-dependent "directory" in a designated S3 bucket: a push to develop is copied to `/develop` and a push to master to `'/production`, similar to the scheme we use for our extra-content repo.  Subsequently, our system uses these bucket contents to create/update the resources that display the "down page".
