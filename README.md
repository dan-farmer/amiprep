# amiprep
Prepare an AWS EC2 instance for AMI generation by removing installed software agents and related config

## Usage
```
amiprep.sh -h
amiprep.sh [OPTIONS]
```

Options:

| Short Option | Valid Arguments | Default | Usage |
| ------------ | --------------- | ------- | ----- |
| -h           |                 |         | Show help/usage |
| -t           |                 |         | Test mode (debug/dry-run) |
| -d           | (rh\|deb)        | Detected from `/etc/os-release` | Override Linux distribution family detection |
| -a           | ssm,codedeploy,cfn,cloudwatch | codedeploy,cfn,cloudwatch | Comma-separated list of agents to remove |

## Warning
This will **deliberately leave agents and instance configuration broken**, so should only be run on a **throw-away instance** that is intended solely for AMI preparation.

## FAQ
1. Why is this written in shell, and not something that gives you more robust control over inputs, better arrays, etc?
   * Primarily, for minimal dependencies
   * As most operations involve control of services and removal of packages/paths, the tools to do this on the command line are readily available, with minimal hoops to jump through
   * This is not intended to be used in untrusted environments with uncontrolled inputs
   * Lastly, this script can be considered a technical exercise - though a previous incarnation has proven useful in production
