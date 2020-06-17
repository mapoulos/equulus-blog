---
title: My Year with Grouper (The Web Application, not the fish!)
date: 2020-06-10 16:25:35
tags: grouper, docker, aws, university-of-maryland
---


Alex Poulos, PhD  
IT Engineer  
Identity Access and Management  
Division of Information Technology  
University of Maryland, College Park  


## Prolegomenon
Why not start a whimsical and serious look at my year with Grouper with a pretentious word like "prolegomenon"? My path to Grouper begain in early 2019, as I was finishing a PhD in Classical Greek and Latin at Catholic University of America (how's that for an origin story!). Rather than going through the hell of the tenure track job search, I decided I'd rather stay in the DC area, and that the best way to do that was to return to a technical career (my undergrad degree is in Comp Sci and I'd worked at IBM while in university). In July, 2019, I started working on the Identity Access & Management (IAM) team in the Division of IT at the University of Maryland, College Park. During my tenure here I've been the primary engineer responsible for our [Grouper](https://spaces.at.internet2.edu/display/Grouper/Grouper+Wiki+Home) deployment; or, as I sometimes call myself in meetings on Friday afternoons, I've been UMD's "Lord of Grouper." This long retrospective is occasioned by a new role: in July, 2020, I  begin a new role as a Full Stack Engineer with the Arc Publishing (i.e. the Washington Post). I'm excited about the new opportunity, but will certainly miss my colleages at UMD. Partly to help my successor, partly to help other deployers of Grouper, and partly to indulge my own penchant for nazel gazing, I've decided to write up a long account of my year with Grouper. 

### What's Grouper?

Grouper is a powerful set of Java applications for managing groups. You can nest groups inside of other groups, do group math, and also do fun things like write custom provisioners or push groups out to an LDAP or Active Directory server. It's being used successfully across North American and European Higher Ed as part of a wide IAM suite of open source tools developed by the Internet 2 initiative. The main deployable components are a web UI (Java web application), WebServices (rest/SOAP web services, another WAR), and a daemon process (that runs to process background tasks).

If you're new to Grouper, I can't recommend the Slack channel highly enough. You have to submit a [request](https://incommon.org/help/) to get in; you can't do this fast enough if you're responsible for a Grouper deployment. The community is extremely friendly and helpful. I would have saved myself a lot of trouble if I had simply signed up sooner!

## How I came to know thee, Grouper. (Or, my stormy relationship with Grouper 2.3)

I began diving into Grouper not long after I started at UMD. It was not always an easy experience. Before I had arrived, the team managing Grouper had been split into an IAM team and a Software Infrastructure team. The latter had been responsible for Grouper (and quite a number of other things); my arrival finally made it possible to hand it over to the IAM team, where it belonged. The developer who had done most of the pioneering work for our deployment had moved to another team, and so the deployment had accumulated quite a bit of technical debt as it shuffled around from dev to dev and team to team. Some of the more amusing (well, painful):

- **Packaging**. In several instances we had needed to get around a bug in the project's code or wanted a new feature (e.g., we added an impersonation feature to use in non-production environments). To accomplish this we had used maven's shade feature to overlay our custom classes onto Grouper jars grabbed from maven central. Everytime we change Grouper code we had to make sure the whole thing still worked as expected. 
- **Deployment.** We were deploying Grouper both on-premise and in AWS:
    + The UI was only on-prem, deployed like one of our homegrown tomcat applications
    + The Daemon was only in AWS, since we had easy mechanisms for running Java daemons in AWS, but not on-prem.
    + The WS were deployed in both places (they'd been moved to AWS for performance reasons but not turned off on-premise).
    + Each component (UI, WS, and Daemon) had a separate bamboo plan for deployment. Deploying a new version of Grouper code meant filling out deploy paperwork three times. 
- **Configuration**. Config was split accross 2 git repos (one for AWS daemon, one for AWS WS) and three AFS unix directories (one for DEV, QA, and PROD respectively, for the UI and WS that were deployed on-premise). As much configuration was shared between components, it was difficult to keep in sync. All the more so because Grouper has an overlay system that sometimes requires an exact path to the overlaid file. This means you couldn't in practice just copy one file, say `Grouper-loader.properties` from one env to the next without tweaking the overlay settings. 
- **Production Problems:** 
    + The daemon process often got stuck processing changes and provisioning group information to external systems. We'd get mysterious NullPointerExceptions in the logs related to Grouper's Point-in-Time tables (PIT) . Grouper keeps full audit information for group memberships over time, but in this case those tables were creating DB inconsistency-related exceptions in production at least once every few weeks.
    + No sanctioned way to run the Grouper shell in production. Our IAM team does not have access to production database credentials, so we had no way to run the Grouper shell to do "maintenancy" type things that couldn't be done through the UI or WS.


How did we get there? First, there was no sanctioned docker container when we began deploying Grouper. This meant that it was easier, at first at least, to treat Grouper like one of our homegrown tomcat apps instead of something built elsewhere with its own needs. The production issues probably had something to do with running the Daemon without enough memory early on: occasionally it would die in the middle of something important, and this caused problems that persisted for months and required weeks worth of sleuthing to figure out. Grouper's documentation has also gotten significantly better since we started deploying the application in 2016. 


## How I came to upgrade thee, Grouper. (2.3->2.4)

Upgrading to Grouper 2.4 was on the radar, but it was doubtful how quickly we'd be able to do this, since the move from Grouper 2.2 to 2.3 had been enormously time consuming. The painpoints above made several things fairly clear. First, we needed to finish our migration of Grouper to the cloud. Happily, UMD has an excellent platform team and a superbly engineered apphosting environment in AWS (at its core built around AWS ECS). The cloud infrastructure was ready for us, we mainly needed to figure out how to get Grouper to deploy well into that environment. Second, we needed to consolidate Grouper configuration to a single git repository, and ideally have a single deploy plan for all three components. 

The first decision to make was how to build the container. We could either continue building Grouper with an overlay and insert it into our base apphosting containers (which we use for in-house tomcat apps); or we could try to adapt the community supported [TIER container](https://spaces.at.internet2.edu/display/ITAP/InCommon+Trusted+Access+Platform+Release). I frankly wanted us to get out of the business of "building Grouper", so I reevaluated our Java customizations to see what needed to remain. The two that stuck out were:

- an overlay to the config loading to allow us to load secrets from our in-house encrypted credential store (it's unclear to me if this was done before Grouper expression language .elConfig was supported for LDAP passwords)
- an impersonation feature

We dodged the first bullet my moving the password logic outside of Grouper's code. Instead of loading passwords dynamically from the credential store at run time, we added some logic to our entrypoint script to fetch the credentials on startup and populate ENV variables (it probably would be better to use expression language to get them dynamically, but this complicated local testing, since we didn't have access to the dynamo tables from our local machines. And boy, was there a lot of local testing!).^[We later wrote the passwords to temporary files in the container instead of consuming them from env vars.] We then determined that the impersonation feature was not worth keeping within Grouper if jettisoning it meant we could avoid building Grouper and the maven overlay. We'd seen that Shibboleth had recently added an [impersonation feature](https://spaces.at.internet2.edu/display/Grouper/University+of+North+Carolina+-+Shibboleth+v3.4+impersonation+supported+by+Grouper+groups) so we decided we could do impersonation that way once we upgraded to Shibboleth 3.4.

Having decided to get out of the "Grouper-building business", it seemed like we should try to work with the sanctioned container as our base.  After several weeks of experimentation, I had something working locally. There were several customizations we needed to make, which included:

- turning off the built in Shibboleth service provider in favor of CAS
- turning off SSL in the container in favor of termination at the load balancer
- moving apache to listen on 8080 and tomcat to 8081 (since by default our apphosting setup expected to find containers listening on 8080)
- adding some Java artifacts (custom connectors, libraries for fetching credentials, health check code to make Grouper look more like one of our homegrown apps)
- adding our healthcheck servlets into the `web.xml` and telling the CSRF guard to ignore them

In most instances this involved copying files out of the container, adding them into our configuration, making modifications, and then ensuring the `Dockerfile` would copy them back on a rebuild. I spent a lot of time `docker exec`-ing into containers to poke around.

With a little more work, we got something up in DEV, and eventually felt secure enough to upgrade our main DEV database to Grouper 2.4; several weeks later QA followed.

On the packaging and deployment front, we settled initially on a two-tiered setup (this ultimately proved more cumbersome than useful). For most internal apps, we carefully version Java code, but not configuration. Generally this means there's a versioned war built by maven that's thrown into a container on a build. We applied the same logic to Grouper, but instead had a "versioned base image". This repo, `Grouper-umdGrouper-base` would take the Grouper base image, install `mod_auth_cas` for apache, and copy in our tomcat/apache/etc configs. This artifact would then be consumed by a "deployable" project called `Grouper-umdGrouper-docker`, which would copy in our Grouper config files (e.g. `Grouper-loader.properties`), other Java connectors (like our custom atlassian connector), and the customized `entrypoint.sh` and `setenv.sh`. We would build one image, and then deploy it to three different ECS services (product stacks in UMD terminology). The task definition for each task would supply an environmental variable specifying which component should run (ui, ws, or daemon). Our Software Infrastructure team then built us a single bamboo plan to deploy all three components at once, which made updating each significantly easier.  By mid November we were basically ready to move to production; for timing's sake, we waited until the first week of December, when we successfully upgraded production Grouper to version 2.4 with no downtime.



### But I digress: PIT will be the doom of me!

In parallel to the upgrade work, we had recurring production problems to deal with. We'd generally notice that the daemon would stop provisioning groups to our LDAP servers, and then look in Splunk to find our logs littered with NullPointerExceptions related to Point-in-Time (PIT) records. This would manifest in two ways: sometimes Grouper's `changeLogTempToChangeLog` job would fail to process a record and get stuck, which resulted downstream provisioners never being notified of group membership changes; other times the downstream provisioners (usually PSPNG, the LDAP provisioner) would themselves get stuck. Because we didn't fully grasp what Grouper was doing here, we would often delete the noisome row out of the temporary changelog table. This would get things going again (or in the latter case, update a DB row manually to tell the provisioner to skip the entry in question).

Only after repeated incidences and much searching around the wiki did I realize that we were actively making things worse by deleting things out of the temporary change log (surprise surprise!). For performance reasons, Grouper does its initial updating of the "live" tables in one transaction (or at least together). A background job (`changeLogTempToChangeLog`) runs once a minute to update Point-in-time tables. This is when change events are moved from the "temporary" change log to the "actual" change log, where they can then be processed by downstream changelog consumers.  In deleting miscreant rows I was actively introducing more inconsistencies into the system (Doh!).

Fortunately, Grouper has [built in utilities](https://spaces.at.internet2.edu/display/Grouper/Point+in+Time+Auditing) for reconciling these errors. Unfortunately, I couldn't get them to run all the way through without them throwing exceptions. I'd generally get some sort of foreign key constraint error somewhere along the way. After many copybacks from production into our dev environment, and much monkeying around in SQL Developer, I eventually ascertained that all our woes stemmed from our "Confluence-Administrators" group. This group had a Grouper rule attached to it that gave it's members admin rights in Grouper over all the groups in the confluence folder. We then were able to observe that whenever anyone was added to a confluence group in Grouper, our Daemon started spewing NullPointerExceptions. 

To fix the problem, I had to do the following:

- delete and re-create the confluence-administrator group
- delete and re-create the rule
- truncate the change log (it gets deleted after 14 days anyway)
- run the built in PIT sync utilities

This required a functioning Grouper shell in production. To provide this, our Platform team stood up three EC2 instances (on for dev, qa, and prod respectively) with appropriate permissions to pull docker containers and fetch credentials. 


### Oops! That time I started deleting groups out of production LDAP
A retrospective wouldn't be complete without a look at the most embarrassing failure for which I was responsible. Early in the Grouper 2.4 development process I was consolidating our config from several different places into one repository. When I finally got it ready to turn on locally in kubernetes, things seemed to be working fine. Until reports started coming in that people were disappearing out of groups in our production LDAP servers.  I had accidentally pointed my local dev container at our production LDAP. (Our lower LDAP environments are paved over each week, which makes keeping distinct passwords among the various environments quite challenging). My local Grouper was overwriting recent changes to the production groups, since our development database was not as fresh as our production database. Rather embarrasingly, I had to turn off my local Grouper, and then prepare an emergency change with an updated full sync schedule for Grouper's PSPNG LDAP provisioners (We were still on Grouper 2.3 and also lacked a way to run the Grouper Shell, so there was no good way to run an adhoc daemon task). Happily the groups were fixed later that afternoon once production Grouper ran a proper LDAP full sync. 



## How I delighted in thee, O Grouper (2.4)

We ran version 2.4 of Grouper in production for about 6 months (at which point we upgraded to 2.5). The improved deploy process made pushing configuration changes and new base code much easier. After our initial 2.4 deployment in December, we upgraded our base image several more times. Only once did this require some changes to our overlay (the name of a base Grouper config file changed).

Our only outage occurred for about 10 minutes during one deploy that went awry: a Cloudformation stack update got stuck and we intervened manually. The way our build pipeline works is that our configuration is stored in a bitbucket repo; bamboo takes this, builds a docker container, and pushes it to our private ECR repository in AWS. A deploy, proper, merely changes a parameter on a cloudformation stack, which prompts the EC2 instances in the cluster to grab the new container. Unfortunately, we'd been stingy with the hard drive space given to these EC2 instances, and the Docker agent's "thin map" space filled up. Effectively, one of the instances didn't have room to pull and unpack the new container, so the update just got stuck. After clearing the thin map space manually (`docker system prune -a` on each box), we stopped the remaining tasks manually, expecting the ECS agent to immediately restart them with the new container. Unfortunately, ECS was rather lazy that day and we were entirely down for about 10 minutes (Lesson learned: never stop your last task running in production, especially when your service is part of the authentication flow of several other applications!).  


### New Capability: Messaging in AWS

The major new feature we added to our deployment during this period was a messaging connector to allow Grouper to post messages to an AWS SNS topic. Each interested application then has its own SQS queue; the combination of SNS and SQS gives us retries and a dead letter queue effectively for "free." (Happily our Platform team had this architecture already worked out; it was ready for us to pick up and run with). We control which groups trigger notifications by using an attribute, much like Grouper's PSPNG LDAP provisioner. Each change event creates a single SNS message, which allows for massively parallelized provisioning. ^[For example, a group of 1600 people was synced to LDAP within a couple of minutes. However, sometimes this is a problem. When I added a 30,000 group to provision to LDAP, our QA OpenLDAP server got very upset as it chewed through its disk I/O balance!] The architecture looks like this: 



At present, we're using this to do some custom provisioning to LDAP not yet supported by the built-in PSPNG provisioner. Soon we'll also be using it to sync Google Groups; it's our new default for any sort of custom provisioner.


### Production Problems: Slow Daemon Jobs

Our main complaint from users during this period was that provisioning to LDAP and Active Directory was sometimes getting stuck. Initially I was perplexed because we'd fixed the PIT errors and there weren't any exceptions in the logs. But then we observed that the daemon job that turns "temporary" changelog entries into "actual" changelog entries was sometimes taking an inordinately long time. This job runs each minute, and shouldn't take more than a few minutes to run (if that). Several times a week, it seemed, it would take hours to complete, sometimes even a day. This prevented downstream provisioners (in this case for Active Directory or LDAP) from getting notified.

I could tell from the logs that things were getting processed, but it seemed that these were "sub jobs" instead of full "jobs." Digging around a bit further revealed that these were sub tasks of a SQL Loader ^[Grouper has the ability to populate a group or set of groups from a relational database or an LDAP server.] that was pulling in Org Chart data from our HR database. This worked in two phases:

- Loader Job #1 would load people into their appropriate departmental group, and create empty roll-up^[A rollup group would capture, for instance, all of the people in the IT department.] groups
- Loader Job #2 would populate the roll-up groups appropriately, based on unit code.

Unfortunately, Loader Job #1 had no idea that Loader Job #2's additions were intentional. So everytime it ran, it emptied out the roll-up groups. Loader Job #2 would run a few hours later and dutifully insert everyone back in. As you can imagine, this was causing inordinate and unnecessary database churn (more than half of our Point-in-Time records and audit records were these nightly deletes and re-adds). Sure enough, the provisioning problems started happening when loader job #1 started running (they were supposed to run at night, but I'd failed to set the timezone for the container; it was running the loader jobs 5 hours ahead of the intended time).

To fix this, we did the following:

- rename the "non" rollup groups to give them a suffix (_basis) (an easy Grouper shell script)
- refactor the SQL for Loader #1 so that
    -   its "LIKE" field only looked for groups with the _basis suffix
    -   it didn't create empty basis groups
- It was perhaps unnecessary, but we also deleted as much of the PIT and Audit data related to this churn as possible  

Once we did this, we stopped having enormous slowdowns and the provisioners have been working reliably since. 

## How I came to upgrade thee yet again, O Grouper (2.4->2.5)

Moving from Grouper 2.4 to Grouper 2.5 was a vastly easier process than moving from 2.3 to 2.4. Once you're running and deploying a containeried, moving to a new one is much easier, even if the container changes vastly underneath (as the container did in Grouper 2.5). Many of the overlays required in 2.4 are no longer necessary. We've utlimately cut down our overlay to these:

* `web.xml` customization to add in healthcheck servlets
* `log4j.properties` to log to a mounted volume (in keeping with our broader platform practice: the volume is ingested into Splunk for centralized Log management)
* UMD logo
* Additions to `Owasp.CsrfGuard.overlay.properties` to allow UMD healthchecks 

We also add in some other things:

* jars for custom connectors (SNS, Oracle, Atlassian, Healthchecks)
* apache configuration for mod_auth_cas
* logic for pulling creds from our credstore

We upgraded initially to 2.5.23 in May and then to 2.5.29 the first week of June. Our upgrade faced a few hiccups:

1) **Auto-DDL Update did not work**. Grouper 2.5 will now automatically update its schema on boot-up (if you opt-in). Yet the auto-DDL update failed to run appropriately against our production database because two views that it was trying to remove did not exist. It's unclear to me just how that was the case (since the auto DDL update had worked fine in QA with data that had been refreshed from PROD recently). But once I found DDL it was trying to run, removed the two `DROP VIEW` bits and ran it manually, Grouper 2.5 came up appropriately. That took about an hour of time, during which the Grouper daemon was out of commission. Happily, the UI and WS remained up with one instance each on 2.4 while the cluster tried to bring up the 2.5 container. 

2) **Connector couldn't find its built-in properties file**. Our oracle connector loads a properties file from within its jar, and then checks the filesystem for further overlays. Because the daemon now runs within tomee instead of as a bare Java process, we had to change a line of code in our connector. For the initial 2.5.23 deploy we reverted the daemon to run as a bare Java process. But for the 2.5.29 update we were able to get it running appropriately under tomee.

3) **Web services required more memory**. We had been running the WS in AWS before our complete cloud migration. When they were initially moved into the cloud, the ECS task definition was only given 800mb of memory (this predated my arrival to UMD and wasn't something I was aware of). This was sufficient for 2.3 and 2.4, but on 2.5, tomcat failed to start-up within the allocated time and therefore failed its healthcheck. This was extremely confusing to debug in our dev environment, because the UI was coming up fine (with 3000mb of memory) while the WS was not, even though they were the same container, and even though both were working fine on my laptop. Once the resources were upped, however, the WS started working fine. 

### Streamlining Internal Packaging and Deployment

As we moved to Grouper 2.5, it became apparent that we needed to rethink our internal packaging and deployment strategy. Our initial "two-tier" packaging process (Grouper Base Image -> UMD Base Image -> UMD Deployable Image) was too onerous for several reasons:

- **Inconsistencies in where Java dependencies were added.**  The build of the base image did a maven build for our custom healthchecks and our SNS connector. Later, during the build of the deployable image, we did another `mvn package` to pull in our other connectors. Running maven twice provided an opportunity to introduce duplicate jars of different versions onto the classpath, which caused some minor headaches in production. It was also difficult to keep track of what particular version of a connector was being deployed, since we had to check two places.
- **Development Bottlenecks and Complexities**. Introducing a change into the base image (e.g. to the SNS connector, or to pull in a new Grouper version) required one to go through a full build process with one bamboo plan, find the image it created, and then substitute this into the FROM line of the `Dockerfile` in the Deployable image git repo. This added 5-10 minutes in round trip time. It was also confusing to keep changes in sync between the two repos (does this feature branch over in the base image correspond to this feature branch in the deployable repo?...). At one point, I mistakenly deployed to production an updated version of the SNS connector because it accidentally got merged into the release branch of the base image repo (Unhappily this broke the downstream dependency, because the message consumer did not get updated at the same time!).

To fix this, we've consolidated all of the Grouper container configuration into a single repo. The Java dependencies are listed in this project's `pom.xml` and pulled in via `mvn package` during the build process. Each Java connector has its own git repo and is independently versioned. Updating Java code for a connector still requires two changes: the updated code is built in bamboo and deployed to our internal maven repo; then we update our Grouper's `pom.xml` to pull in the new version.  Yet it's much clearer what version of what connector is deployed at any given time. 

### Plans for the Future

#### Collocated Database

We've a variety of plans for what comes next for our Grouper deployment. Probably the most important for performance will be shifting to a collocated, dedicated database. This is a standard Grouper best-practice that we haven't been able to implement quite yet. We are (despite ourselves) still an Oracle shop, and our Oracle servers are still running in VMs in our on-prem datacenters. Even though College Park, MD is not far from Amazon's us-east-1 in Northern Viriginia, we still incur an extra couple of milliseconds of latency between the on-prem datacenters and our appservers in AWS. This ends up making a pretty big difference for an application like Grouper that really taxes the database.  

For a variety of reasons (organizational and technical), we probably won't be able to migrate to using something like Aurora in production in the immediate future. But we have been able to test in an engineering environment. After banging my head against CloudFormation for a day or two, I managed to stand up an Aurora Postgres cluster with a single RDS instance. Loading it with test data was a bit tricky. With some help from Chris Hyzer I was able to use the [experimental migration tool](https://spaces.at.internet2.edu/display/Grouper/Grouper+database+migration+utility) built into Grouper 2.5.24+ (I had initially not set up the Grouper user correctly in postgres). It took about an hour and a half to load our production data. To compare performance between AWS Aurora and On Prem Oracle, I measured the amount of time it took to load the same pages in the ENG environment (Aurora) and our QA environment  (Oracle).  

| Group  | AWS Aurora Page Load (AWS DB+Appserver) | On-Prem Oracle Page Load (On-prem DB + AWS appserver) | Speed-up Percentage |
|--------|---------------|-------------------|----------------------|
| Home (testuser) | 0.1 s  | 3.5 s |  (a caching fluke, it seems) |
| "My Groups" (admin)| 3.2 s  | 9.7 s  | 303% |
| medium group (1600 members) (testuser)   | 1.8 s  | 6.2 s  | 344% |
| Home (admin)   | 1.0 s  | 3.7 s  | 370% |
| large group (12k members) (admin)   | 1.4 s  | 2.9 s  | 207% |
| "My Folders" (admin)   | 1.2 s  | 5.1 s  | 425% |


## Special Thanks

I'm really thankful for my colleagues at UMD. My managers, James Gray and Will Gomes, were extremely supportive and fought to do things the right way, rather than the expedient way. Stephen Sazama was my first Grouper mentor. My teammates, Noel Nacion, John Flester, Noel Nacion, and John Pfeifer have continually asked good questions and helped improve Grouper. Finally, our Platform Engineering Team, especially Eric Sturdivant, has been instrumental in making Grouper a low-risk application to deploy and run.  

I'm also really grateful for my experience with the wider Grouper community, a few of whom I even got to meet at TechEx! Chris Hyzer, Shilen Patel, Carey Black, and many others have provided helpful advice on how to best deploy this powerful and complex tool.  



