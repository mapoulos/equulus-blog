---
title: 'Location, Location, Location'
date: 2020-07-31 16:51:11
tags:
---

## The Task
For my work with [CrossCut](https://crosscut.io), I’ve needed to get some R scripts running on big EC2 instances to do some geospatial processing. This involves loading in a bunch of files of various formats (CSVs, TIFs, and also SHP files).  The R scripts were written by a colleague; they naturally are tested first on his laptop and assume that data is going to be read from the local filesystem.

## The Problem
As expected, we’re storing the inputs needed in S3. At first, I thought this meant I’d replace the local filesystem load function with S3 equivalents (R has several s3 libraries to choose from: [paws](https://github.com/paws-r/paws) and [aws.s3](https://github.com/cloudyr/aws.s3/tree/master/R)). There’s a nice helper function in the *aws.s3* library that lets you save the file to local disk and load it in one go. So I thought I’d go through the code, consolidate the external resource loading into one place, and then would swap in cloud equivalents. Basically, it would look like this:

```r
#before: local load
data <- read.csv("myfile.csv")

#after: cloud load
s3read_using(read.csv, "s3://<my-data-bucket>/path/to/myfile.csv")

```


This proved to be a pain because Esri SHP files contain references to other files that also need to be pulled to run locally. For example, `my-shape-file.shp` might contain references to `my-shape-file.proj` and `my-shape-file.dbf`.  If all of these are not present, loading the SHP file fails.
 
At this point, I thought I’d have to write a function in R that would take a shapefile, download it, and be smart enough to pull in any other files with the same name but different extensions. Not terribly complicated, but not fun to do in a language you don’t know that well. And it would have made the split between running locally and running in the cloud even greater.

## The Solution
When describing the problem to my wife, who’s also a software developer, she asked a simple but insightful question: “do you have to do that in R?” I responded at once with a firm “yes!” but then thought about it a bit. “Actually, I can do this in the entrypoint bash script…” 

This proved to be a much simpler and elegant solution. When the docker container is launched, its entrypoint script fetches the data needed from S3 using the `aws-cli` tools. Instead of iterating over files and being clever, we simply pull down all the data for a given country locally, and put it where the R script expects to find it. The relevant bits of the entrypoint look something like this:

```bash
s3_population_dir="s3://$S3Bucket/data/crosscut_data/data/$COUNTRY_CODE/"
export local_population_dir="/data/$COUNTRY_CODE/"
if [ -d "$local_population_dir" ]; then
  echo "Found data baked into docker container"
else
  mkdir -p "$local_population_dir"
  echo "Fetching data from s3"
  aws s3 sync "$s3_population_dir" "$local_population_dir" 
fi
```

## Observations

Context switching is hard. Like many Full Stack devs, on any given day I’ll touch some front-end JavaScript code, then move to back-end Java, write a MongoDB query, or futz about with an NGINX config or CloudFormation template. The most important decisions a technologist makes are often not about *how* to implement any given piece of a system, but *where* in the system responsibility should lie for a given task. In this case, it’s actually much better for the R code to be dumb about how the files get to it. By making the code work similarly in both a cloud and local scenario, we’ve made it easier to updates to the code, since we don’t need to add extra logic (or worse, change the code manually) when running it in the cloudl

