This is a set of scripts that will allow you to containerize the excellent ALM system **[Polarion](https://polarion.plm.automation.siemens.com/en/application-lifecycle-management-alm-tool-trial)** from **[Siemens Digital Industries Software](https://www.sw.siemens.com/en-US/)**

 1. Download the contents of the [polarion-build](https://github.com/Krusty84/Docker-Polarion/tree/main/polarion-build) folder
 2. Place your **Polarion Linux ZIP package** (e.g., PolarionALM_22_R2_linux.zip) near the **Dockerfile**
 3. Build the image: **docker build -t polarion:latest .**
 4. Launch a container with Polarion:
**docker run -d --name polarion --net=host -e ALLOWED_HOSTS="0.0.0.0" polarion:latest**

*for example:*
docker run -d --name polarion --net=host -e ALLOWED_HOSTS="0.0.0.0" polarion:latest
After some time you will be able to access your containerized Polarion: http://localhost:8080/polarion

**Note**: This build supports multiple Polarion versions and architectures (x86_64/ARM64). The Dockerfile will automatically detect and use any Polarion Linux ZIP package in the build directory.

<p align="center">
  <img src="https://github.com/user-attachments/assets/8dc3207d-676a-4912-8aaa-ed7786b87c89">
</p>
