# quickstart-sas-grid
## SAS Grid on the AWS Cloud

This Quick Start deploys and configures SAS Grid on the AWS Cloud.

SAS Grid is a shared, centrally managed analytics computing environment that features workload balancing and management, high availability, and fast processing. A SAS Grid environment in the AWS Cloud provides the elasticity and agility to scale your resources as needed.

This Quick Start bootstraps the infrastructure for a SAS Grid cluster by provisioning Amazon Elastic Compute Cloud (Amazon EC2) instances for SAS Grid, SAS Metadata Server, and SAS mid-tier components. It also deploys SAS Grid into this infrastructure and sets up DDN Cloud Edition for Lustre, which provides a shared directory for the grid. 

The AWS CloudFormation templates included with the Quick Start automate the following:

- Deploying SAS Grid into a new VPC
- Deploying SAS Grid into an existing VPC 

You can also use the AWS CloudFormation templates as a starting point for your own implementation.

![Quick Start architecture for SAS Grid on AWS](https://d0.awsstatic.com/partner-network/QuickStart/datasheets/sas-grid-on-aws-architecture.png)

For architectural details, best practices, step-by-step instructions, and customization options, see the [deployment guide](https://fwd.aws/zavnn).

To post feedback, submit feature ideas, or report bugs, use the **Issues** section of this GitHub repo.
If you'd like to submit code for this Quick Start, please review the [AWS Quick Start Contributor's Kit](https://aws-quickstart.github.io/). 

test change
