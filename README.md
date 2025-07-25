
# Task 7

 Deploy a strapi application on AWS using ECS Fargate, managed entirely via terraform
Create a new repo 
add a git workflow to create a fresh image, apply tagging and push in your registry
then update the task revision to use the new image
Accomplish all the above using git action only.

## Steps
### 1. Update ci.yml 

To Build and Push docker image on ECR repository.

### 2) Update terraform.yml

IF resources exists THEN create new task definition and update ECS service; 

ELSE create all new resources (terraform apply); 
 
### 3) Push the Code
ci.yml will trigger by pushing the code on main branch.

     git push origin main

### 4) Trigger terraform.yml
Manually trigger the terraform.yml workflow with image tag as an input.

### 5) Access ALB dns name

Access ALB dns name at port 80 to access strapi admin panel deployed on ECS.

## Results 


### ci.yml Workflow :
![](t7/build.png)

### terraform.yml Workflow : 
![](t7/terraform.png)

### New Task Definition : 
![](t7/CreateOfNewTaskDefinition.png)

### New Task :
![](t7/CreationOfNewUpdatedTask.png)
![](t7/NewTaskWithNewTaskDefinition.png)
### Strapi Admin Panel on ALB Dns Name Before updating ECS task and After updating ECS task: 
![](t7/BeforeAndAfter.png)
