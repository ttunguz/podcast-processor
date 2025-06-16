 [MUSIC]
 >> Welcome to the Yet Another Infra Deep Dive Podcast.
 As usual, Tim from Essence and let's go.
 >> Hey, this is Ian, super excited.
 Today we have the founders of CedarDB on the pod.
 Moritz and Chris, welcome.
 Can you tell us a little bit about yourselves, but more importantly,
 what is CedarDB and why am I excited about it?
 >> Sure, so hi, I'm Moritz.
 I'm one of the five co-founders of CedarDB,
 and I'm joined by my colleague Chris.
 To quickly answer what CedarDB is,
 we like to call ourselves the all-in-one database system.
 In a sense, it is what Postgres used to be for the 90s and the 2000s,
 but built for the hardware and data processing you have right now.
 Its core of CedarDB is just a SQL-based relational database system,
 and it's also compatible with Postgres via protocol and its grammar,
 which means that it allows people who are used to working with Postgres
 to work with data but much faster and much more efficient.
 >> Amazing, so go ahead, Chris.
 >> Just wanted to add to the intro.
 Yeah, we're really excited to build something that finally makes it easy again
 for people to analyze the data without having to work with tons of tools and
 learn tons of languages, just make it simple like it was in Postgres.
 >> What's the primary innovation?
 Postgres of the 90s, CedarDB is 2020s that enables it.
 Primary differentiator in the data world is OLAP or OLCP.
 Does CedarDB solve that problem?
 You say it's an all-in-one solution,
 like help me understand what it is about CedarDB that makes it the future.
 >> Right. So, CedarDB by itself,
 I think what differentiates it's most to many other database system is that
 it is built from scratch and it is designed for the current hardware you have right now.
 And this really goes through all the components that CedarDB has.
 So, if we start with our query optimizer,
 it can generate efficient query plans even for deep NASA queries with hundreds of
 joints, which means that as a user you can finally just write SQL without having
 to think too much about what the database will do with the query and how it executed.
 And then, of course, CedarDB then takes these optimized query plans.
 And what we do with this, we compile them to efficient machine code directly.
 So, essentially, this gives you the performance similar to a handwritten
 C code for every individual SQL query, which makes use of the specific CPU
 you have in the instance where CedarDB is running on.
 And then during query processing, our buffer manager is also designed to
 effectively utilize large memory sizes, which on today's servers you can easily
 get a few terabytes, right?
 So, what we do is that we can reach main memory processing speeds as long as your
 data size fits entirely into main memory.
 And we gracefully slow down to the speeds of NVMe SSDs or cloud storage
 as soon as the processing will do exceeds the memory capacity.
 And all of these components together allow CedarDB to easily outperform all
 the other database systems that you have right now and even non-relational
 database systems, so you can also run other use cases such as graph processing,
 stream processing, all of this in CedarDB and combine them with, you know,
 traditional relational data processing.
 >> It's been a while that we've been hearing about like these sort of HTAAP
 systems or like these like combined different systems, but not many people
 actually tried it.
 I think that's a reality.
 From research point of view, I think it's pretty like research and
 been well understood, but then industry wise, I don't think there's actually
 that prevalence of usage yet.
 Maybe can you talk about like the history of these sort of like products or
 systems like like is there, is this mostly been a research only?
 Like, have we seen any commercial products at all?
 Talk about like what has been the reason why we haven't seen everybody
 just start using this everywhere?
 >> So I kind of disagree there that there isn't really an HTAAP product out
 there because Postgres, for example, is like a prime example of an HTAAP system,
 a system that can do both transactions and analytics.
 It's just that people don't perceive it as such because it's just like a
 database system that's always been there.
 And so in a sense, I think that a lot of people use HTAAP systems,
 but they don't actively call them that that's what they're used to with a
 database system in general.
 And so I believe that there are quite a few workloads for those.
 Of course, in the past, we've seen like the transition away from
 a single system such as Postgres to a more diverse landscape where you have
 a system specifically for your analytics, big data warehouse like Snowflake or
 like BigQuery and so on.
 But in a sense, that was only out of the necessity of Postgres not being
 able to keep up with the current workload.
 And why we haven't seen that many other products being built is,
 it's not that easy to build an HTAAP system from scratch, right?
 I mean, we've taken five, six years in research with a lots more team by any
 means and like not many people have the chance to work on such a project for
 such a long time without actively having to deliver something between.
 And so like building this deep integration of transaction processing,
 analytics and everything fast as well is something that's quite the engineering
 challenge.
 And so I think that's the reason why we haven't seen this because for most
 people, which have a small workload, which don't have tons of complex analytics
 running at the same time, Postgres still scratches that itch, right?
 It still works just fine.
 It's still a great system.
 And for everyone else, they were fine with building data pipelines into Snowflake and so on.
 I think I agree, yes.
 There's Postgres and all those are variants even come before that, right?
 We grew a lot from a database world from even going to relational, right?
 And actually shoving a lot more data over time.
 But there's a point I think you just talk about the database history in a more
 recent years is an explosion of databases, right?
 There's so many databases now, so database almost feel like for
 everything, not just vector database for AI, but like graph and time series.
 And the whole nine yards, like, you know, I think it was fundamentally, you know,
 maybe just kind of like for context, what do you guys think the explosion seems to
 happen because this one size system fits all, at least for Postgres, wasn't
 possible, right?
 To push for certain kind of queries, push for certain kind of workloads.
 And like I said, like technical limitations, probably order and demand or
 needs of the data has changed quite a bit.
 And maybe can you talk about like, what are actually is the main challenges
 when it comes to like trying to combine workloads?
 And I don't think you can combine all kinds of workloads,
 like combine all world history of databases or recent history into one, right?
 So there's probably certain kind of things that seems more suitable to fit
 into Htasticism, I assume.
 Because I think this is kind of the interesting part is like, how do we start
 thinking about the fundamental things that are changing through a cedar,
 something like cedar that can work here?
 So we can talk about a little nuance here, like, what are the biggest things
 that are happening that makes a database like yours actually can work?
 And what kind of workloads can actually consolidate into your all-in-one database?
 Like you said, there's tons of different database systems that you can get today
 for very specific workloads, such as graph processing.
 But I think if you look into what the actual tasks
 behind these systems are, they're quite similar.
 Mostly for analytical systems, this is like loading data from your storage,
 be it internally or externally transforming it, so filtering it for certain attributes
 or certain values or certain combinations, combining it with other data.
 So in graphs, you will have hops and you have like edges between nodes
 and in the relations, you will have joins and so on. But the concepts of these
 are very similar and they're not that different to process.
 Semantically from the outside and from the languages that you interact with these,
 they're quite different.
 But if you look down into like the individual components or individual steps
 that the system has to take in order to process this data,
 this is very similar for a vast majority of like fixed data,
 less as I would call it, so something that's not highly interactive
 and changing all the time.
 So as long as you can scan statically data and analyze it,
 I think it doesn't matter that much if you want to see it as a graph
 or if you want to see it as a semi-structured JSON document
 or if you want to see it as relations.
 I think like these steps that the system has to take are pretty similar.
 And so starting from this, then building a system like ours,
 if you get these basic blocks right and if you're good at filtering data
 and if you're good at combining data with other data,
 I think building these workloads is quite easy.
 Of course, you're right, like there are workloads that are not a natural fit
 to this model, but the vast maturity of people we've spoken with,
 like they are fine with the support that like maps down to these components.
 And, of course, there will always be niche workloads
 where you have very specific graph algorithms that simply need to be built again.
 But for the vast maturity of like three, four, five, ten pops in a graph,
 you can easily do this with the same mechanisms that need a database system for trends.
 I'm really curious to understand, you know, in the traditional enterprise,
 you've got your data warehouse, maybe it's stuff like maybe you're doing some
 data break stuff, Delta Lake, you've got a bunch of old to P store.
 So a bunch of Postgres instances all over the place got online offline.
 You've got ETL systems moving data from the Postgres synthesis into the into the
 warehouse and maybe you've got some reverse ETL moving stuff from the warehouse
 back into the online processing or maybe into some SaaS like what of that
 cacophony of moving pieces of bubblegum and popsicle sticks that is a modern data
 infrastructure, like if you adopt cedar DB, like what of that cacophony of stuff
 are you replacing that you don't need anymore?
 Because, you know, we've solved this problem, like for the simple
 folk, like is all the LTP stuff together.
 And just inside cedar DB, like help us understand.
 The nice thing about cedar DB is that essentially this choice is up to you.
 So you aren't forced to really replace your entire data stick up front.
 But of course, in the ideal world and in what we think should work best is
 that you combine most of your OTP and analytical workloads and ETL and reverse
 ETL all into the same place, into one single source of truth.
 And because this really allows you to get rid of all the downsides of having
 such a complex stack, right?
 If you have 10 systems, you need to transfer the data between them, which,
 I mean, if you're running ETL pipelines, if you are lucky, they are running
 every night, but the delays can be even longer.
 So you will necessarily have delays and then, of course, you will have the
 problems with synchronizing data and between all of the systems, which, for
 example, make your analytical results potentially out of date, which could be
 an issue if you're doing like more modern data processing, where your data
 results result in automated decisions or in any other automated processes, which
 rely on the analytics results to be precise and correct.
 And if you have everything in a single system, which CDDB can do, you'll
 necessarily get rid of all the delays, now caused by ETL, and you have only a
 single version of your data, which immediately makes this consistent.
 And of course, since CDDB is a transactional database system, you have
 real transactions over your entire data and your analytics run on the same
 systems as your transactions do.
 So even all your analytics will be part of this transactional semantics and
 will also be guaranteed to be correct.
 So to answer your question, ideally, you want all your data to be in one place,
 but CDDB specifically allows you to gradually start out with replacing some
 of the applications or some of the data storage you have by replicating the data
 you have lying around somewhere else, and then gradually switching, you know,
 replacing existing systems one by one.
 Really interesting. And so help, help me understand like the scaling semantics.
 So like one of the reasons we've ended up in the world where we have, you know,
 tens, hundreds, for some people, thousands of divinal to piece database
 instances and, you know, many divinal warehouses is scaling, right?
 It's like, we started this world where it's like, okay, we're going to, you know,
 15 years ago, we talked with three tier app where you had, you know, your UI
 layer, and then you hedge your sort of like business logic layer.
 And that was probably one ginormous Java app.
 And then you hedge your like massive Oracle instance and you basically
 build your entire business on top of that.
 Like that was a go to stack.
 And a bit of what it sounds like you're telling me is like, actually,
 CDDB is the pathway back to that world.
 Now, is that true?
 How do you think about the scale of the data, the different workloads?
 Like, are these different, is it the same format and protocol?
 Are there different instances?
 Like if you were to prognosticate, you know, your middle,
 your mid-sized enterprise or even like your mid-market company,
 like, how do you think about the way that people deploy CDDB and
 the optimum use cases for CDDB?
 And what do you simplify for them?
 It's really interesting, the idea of HTap, but we went to this
 world of like thousands of different databases all over the place for a reason.
 So help me understand what CDDB is solved specifically.
 And is it like one instance?
 Is it many instances?
 Like what's the deployment topology and why?
 To answer the easiest question, the topology of CDDB is that we do data
 processing on a single node only, and we distribute only the storage.
 So that's the easy answer.
 The reason why we believe this is the correct approach has, I mean,
 there are many answers to this.
 One of the answers is that people will rarely actually need real distributed,
 especially transactional processing and for the amount of data they have.
 You do have companies like Google, like Amazon, which will process petabytes of
 data every day, but this is not your typical customer, right?
 So your typical customer will have terabytes, a few terabytes of data,
 which nowadays can fit even into main memory of the largest AWS
 instances you can buy, right?
 They have, I think, around two terabytes of memory right now.
 So there's easily enough capability, even in main memory,
 to process the vast majority of all customers' needs on a single node right now.
 I mean, because of this reason, we also believe it's much easier to build
 a very efficient system on a single node, right?
 So you don't have to think about, especially distributed transactional processing,
 involves a lot of consensus protocols and all of this,
 which necessarily make things lower, which, I mean, you can't really avoid this.
 But you can get most of the, as I said, most of the current processing will
 easily run on a single server anyway.
 And if you have a system such as CDDB, which is so much more efficient and
 faster than all the other systems you have, then it's much easier to really
 deliver on this promise of, okay, you just need a single server.
 Because what you also believe is that the reason why people in the last decade
 or so tended to distribute their data processing heavily is that no system
 could really utilize the, like, for example, 200 CPU cores you get on a large CPU server.
 So instead, you use, like, for example, Spark is a very popular and
 a very efficient system for doing easy distributed processing.
 But if, for example, our system, I mean, this heavily depends on the worker,
 but if our system is 100 times faster than Spark, you can easily, I mean,
 that's pretty obvious, you need only 100 of these servers.
 So if you have a cluster with 100 servers right now,
 you could replace it maybe with just a single instance of CDDB.
 >> So that's actually really fascinating.
 I think you actually put it in a very interesting way of that.
 Instead of thinking of how many servers and
 how many distributed computing really think about, because most of the frameworks
 these days, I think at some point, even like a Mongo or Influx,
 all of these, at some point production has to be clusters and more nodes, right?
 And for compute layers, like the Spark of the Worlds has been
 famously talking about, like, how many thousands of nodes you can run
 with, like, how many big of data sets, right?
 And that was the way to make it more commodity hardware type.
 And people get used to that, and that's why we even spend money to have other
 people manage those fleet of clusters for us.
 But when you think of a CRDB, I guess you're saying, like, a single node
 performance and pushing that limits and reimplementing can make a huge difference here.
 And so how do you think people are going to change the way they actually operate with data?
 Because data right now, the assumption is not going to fit in a single node anyways, right?
 There's no single disk second hold all data.
 So you put everything in S3, and therefore you can have a scale out compute.
 And the compute storage separation has been pretty much a standard for everything now,
 warehouses, the whole nine yards.
 But if you have put a single node computing, do you still treat compute storage separate?
 You know, how do people think about actually the data itself when you think about CRDB?
 Like, are you back to the world of post-cresses where everything is shoved into a single disk?
 And we all run there and with the rate and kind of stuff.
 Or we actually can actually leverage your big server compute power with still the scale out data.
 Does CDRAD-BD have a different philosophy when it comes to this sort of data and compute relationship?
 No, I would definitely say that the separation between compute and storage is definitely there
 to stay. So you get tons of memory and even tons of SSDs in a single disk, right?
 People tend to store a lot of data. Even if they don't look at it that much, right?
 If they have the data, storage is cheap, especially with like stuff like this three,
 which basically comes at commodity prices, right? You don't have to care about how much
 you store. It's pretty cheap per month. So I definitely think that separating the compute
 from storage is there to stay. But what isn't necessary is distributing the compute itself.
 So I mean, you can have different instances, but one instance can definitely serve one query.
 So no need to distribute a query over multiple workers. And at the same time of what Moritz
 talked about before, distributing transactions is also not something that's going to be necessary
 for a ton of folks. But we definitely will distribute that storage and can also read from S3 and other
 cloud object stores. I'm really kind of interested. I mean, this is like not some bolts of like what
 different say to CRDB. And so one of the questions I wanted to ask you was, what are the challenges
 that make Postgres not scale? And I mean, you're kind of answering that question, right? Like these
 fundamental things. Of the challenges you've had to solve to create CRDB, what has been the most
 difficult thing to get to the point that you are today? Like, what has been the biggest
 technical challenge to overcome? Because for a long time, HTAP has been this like, it'll never
 happen. These are completely polar opposites. The world, this is not possible. And then y'all
 come along, you'll want to see the DB and we have this database, I can do relational graph data,
 I can do analytics workloads, I can do transactional workloads. So is there like one thing?
 Is the architecture that opened up the opportunity? There are multiple different
 things. And of those things, it was like most difficult to figure out.
 We definitely don't think that there's only one component that you could, for example,
 improve in Postgres to make it as fast as CDDB. So it's definitely a combination of many things.
 But there are definitely are some things which were harder than others. So one thing is that
 by design, every query in CDDB always runs on all the CPU cores you give it. So this is
 something that's very different to especially Postgres, which is just now starting to
 parallelize some of the operators. But a very important philosophy of CDDB's query processing
 is that from start to end of a query, all your CPU cores should always do useful work.
 And this requires you to rethink a lot of the algorithms that you usually use in data processing.
 For example, I mean, just sorting data, it's just inherently not easy to fully parallelize.
 I mean, there's a lot of research in how to actually do this. But there's also other things like,
 "Okay, you have joint processing." And a lot of other things that Databases usually does,
 how can you make sure that essentially if you look at your CPU utilization on your server,
 that it will always be on 100% from start to finish. So this is one thing, which requires a lot of
 rethinking of algorithms. And the other thing is the hard drives you have right now, like SSDs,
 they have very, very different performance characteristics to traditional magnetic spinning
 hard drives. So, for example, it's not as bad anymore to do non-sequential accesses, which is
 the number one performance killer for magnetic drives. But you have different things. For example,
 you have the blocks internal box sizes of an SSD. It's much larger than the 4 kilobyte page size.
 So you need to rethink a lot of how you can access this SSD, because it gives you a lot of
 more performance, but only if you access this correctly. And then, of course, you have some more
 things like modern transactional processing and multi-version concurrency control in all of this,
 which also ties into, you know, multi-user support and scheduling and all of this.
 So there are certainly a lot of components, but I hope it could give you a bit of an idea
 for us the most challenging things were.
 So I want to ask, reading our blog posts, kind of like talking about Postgres and
 introducing CedarDB. And then one thing I kind of like caught my eye, you know, beyond what we
 talked about is I think the fundamental thing about having an all-in-one database systems
 isn't just combining the sort of capabilities. The user will mention like there's has to be
 also a very simple base layer. So I guess the idea is not to really complicate the interface.
 So like you have a graphical, you know, you do Cedar and do pretty much like every single
 possible thing here at Key Valley lookup. And, you know, everybody has basically reinvented
 some kind of query language at this point that seems well suited for their workloads and make
 it somewhere simple, but it's really complicated explosion. But then I wonder like, how do you
 decide what's the base layer of operators that you should put where it also doesn't make transitioning
 from any database into you almost seems impossible? Or maybe it's possible.
 Is there a thought process here? Like, how do you think about designing that interface
 and figure out what other transitional paths it is? Because it's basically not
 backward compatible to any other database at this point, right? If you're using Cedar for graph,
 you got to rewrite it, right? I assume, or using some SQL language that everybody has a different
 SQL, you might need to like migrate, right? Correct me if I'm wrong, assumption here. But that's kind
 of what I feel like I understand based on your statements. But talk more about like how you
 just think about the interfaces and think people can able to transition to you in a more seamless way.
 So I think a big part of our strategy there is being as compatible with Postgres as possible,
 right? Because tons of systems today have interfaces with Postgres. And so we basically
 reimplemented the Y of protocol. We also reimplemented the SQL grammar in a sense there. So that
 wherever you're using Postgres SQL, which a lot of tools offer us like the basic choice,
 then you can also simply use us without much hassle. So you can keep your tools and so on there.
 And this also of course goes for the add-ons there. So for example, for vector stuff,
 we're implementing the Pgvector extension interface and so on. But you're of course right that there
 are some use cases which have seen their own languages like rough processing. And for those
 right now, like most of them, and we will have a blog post on this very soon, depending on when
 this error is, it will probably already be out. It's like it's not that hard to express these
 typical graph queries of a few hops in SQL as well. And of course, supporting a graph language
 in the end just comes down to parsing the grammar and translating it into our internal operators
 like joins and filters and scans and so on. So I'm definitely not excluding the possibility that
 we will have a graph language interface at some point. But right now, there is not like the
 CGL standard came out recently. And we're still not sure if this will get adopted or
 people will stay more closely with the Neo4j cipher language. And so for now, most interfaces
 that we will focus on are these PostgreSQL based ones, because that's just something a lot
 of people are familiar with, not only for Postgres, but also for other systems like Aurora,
 or RDS in the cloud and so on, which also depend on these tools.
 I'm really curious. One of the things, I was having a conversation with a friend of mine
 actually yesterday about Postgres, and he looked at Postgres 16 and was really interested in all
 the new features. I've come out in the last four to five years, or of course, all scaling, which
 exists before. It's just the ecosystem of Postgres is phenomenal. I'm curious, you know,
 how do you think about competing with Postgres's plugin ecosystem? And the sort of this core,
 they had this core spire, and they have all these plugins effectively extensions,
 database is a system for front-end developers, right? You don't have to own the back-end
 back-end list, it's back-end is a service or whatever. I'm kind of curious, like, have you thought
 about an extension system and how you build or enable an ecosystem like Postgres is on top
 or see the CDDB? Have you thought about it supporting their extension ecosystem, and how
 production-ready do you think CDDB is in general today? And where do you think it is in terms of
 like your ability to, you know, should sneak use it? Is, you know, kind of my question.
 So to answer your question about whether we are intending to support Postgres plugins right
 away, the answer to this is no. The way Postgres processes data and process queries is fundamentally
 incompatible with how we process data. So every plugin assumes that, like, where we will run
 on a single thread only, and since we compile to machine code, this is also done very differently.
 So we don't support Postgres plugins directly, but we try to find which Postgres plugins are
 more popular, such as PG Vector as Chris said, which seems to be very popular for
 vector processing in Postgres, and try to incorporate them in CDDB directly as well,
 with more efficient implementations. And of course, I mean, many plugins that we also see,
 they purely exist because of some downsides of Postgres, right? So you have plugins which
 try to improve some performance aspects, you have plugins for cloud storage or plugins which make
 parallel processing easier, or they loosen up some of the traditional guarantees to allow
 you to process the data more quickly. I mean, since our database system is so much faster than
 Postgres anyway, we also think that many plugins may not necessarily be required for use in CDDB.
 Of course, there will always be things that CDDB will not offer as if you have some very
 specific data processing needs. And for this, we support user-defined functions. I mean,
 of course, user-defined functions, everybody knows them. And people tend to not like to use
 them for many reasons. One is that often, for example, in Postgres as well, or also like in
 databases like Oracle or Microsoft SQL Server, you have to use a very specialized database
 kind of SQL dialect, which allows you to write algorithms. And obviously, no one wants to write
 their AI inference, whatever, in the SQL-based language. So we, in that case, we can also
 exploit the fact that we do compile to machine code. And if you have an algorithm written in a
 language like C, C++, Rust, any of the language that compiled to machine code as well, we can easily
 combine them with the code that we generate for the SQL queries. And this allows us to
 essentially also get the same performance, like the handwritten code performance for custom code
 you've write, but you can still combine it with existing functionality, like aggregations, filters
 and joints and all of this in a single database. Right now, we do have our own SQL dialect for
 these kinds of algorithms as well. And we are currently working on making our
 UDF implementation more stable and production ready. So maybe if you're interested in this,
 I can go into a bit more detail there. So in general, how this will work, that we support
 WebAssembly as essentially an input language for user defined functions. So you can run
 untrusted any, the end kind of untrusted code very efficiently in the database system and
 combine it very easily with all your, yeah, all your other workloads.
 Awesome. Well, we're going to jump into a section we call the spicy future.
 As it's very self explanatory, we want you to guys to tell us what you believe that not many
 people believe yet. And spicy. Chris, why don't you start with yours and school from here?
 Sure. So I think Moritz has already taken some of that away in our discussion before,
 but I think a large part of what I believe is that the amount of distribution that is so today
 is not something that will be necessary even in the future for a ton of people.
 Like there will always be some outsiders that really need petabytes of intermediate states,
 but for the vast amount of people, even if you're crunching petabytes of data,
 your intermediate results will not be petabytes. And for those people, it's always better to stay
 on a single machine if you can, and just make the most use out of the hardware you have without
 getting all the overhead and kind of distributing to get a minimal gain in that area.
 Interesting. Moritz, how about you? You know, I have a very different hot take. Maybe it's
 more of a mild take because I think people are starting to realize this right now,
 but I think SQL is a great language. SQL was designed in the '70s, '80s, like this. And it has
 shown that it's still very relevant today. And the reason for this is that SQL has been designed
 in a way to not prescribe how a database has to execute the query. And this has led to
 database systems right now, such as SQLDB, they can choose how they want to execute the
 SQL system themselves, which means that the SQL statement you've wrote in the '80s will run
 much, much faster right now, even though you didn't change any of the code. And to add on that,
 I think many languages or many database systems tried to think of new languages. I mean, of course,
 you have document-based database systems, such as MongoDB, which try to come up with their own
 language. You have things also like object relational mappers and all of these libraries.
 I strongly believe you should just write SQL directly. So you can do JSON processing in SQL
 as well, like CBDB supports the same syntax as Postgres does. It has been shown here for
 year and for every new system that everybody tends to go back to SQL anyway. I mean,
 MongoDB supports SQL, and you also have the SQL adapter to spark, for example.
 Yeah, I think it was just great. And this is why we're also still building on SQL,
 and we are still intending on continuing to do so. And yeah, a strong believer in SQL.
 I mean, those are spicy, both of those are spicy, because if the average bear, I think,
 would say, I don't want SQL and the other average bear would say, I believe in a distributed
 world. So it's really interesting to think through that spicy feature. Do you, where do you align
 around things like object store? Like, we think about cedarDB and the future of cedarDB,
 and you think about the future of object store. Like, does that play into how you think about
 your database design? It sounds like no, because you really want to run on like, is close to the
 bear hardware to get managed of SSDs and those other things. Like, how do you think about the
 ecosystem and how it evolves as cedarDB becomes more mature, gets more adopted? Like, how is it
 change the rest of the ecosystem? So do you mean things like S3 with object storage?
 Yeah, I mean, so we do want to work very closely to the hardware, because that's the only way to
 really get all of the performance that you can get with modern hardware. But we definitely think,
 as Chris already touched on, separating compute and storage makes a lot of sense, and you will
 need to do this. And for this, using object storage is like S3 just makes sense. That's the
 obvious way to do this. And our entire data storage model, like the internal data representation of
 cedarDB, is designed specifically with object storage in mind. So we have certain block sizes,
 we have a columnar blockwise storage, which makes it very easy to separate this into different
 blobs and makes it very easy to access this efficiently and also cost effectively. Because,
 storing data in S3 is cheap, but accessing it can be very expensive if your system doesn't
 do this very efficiently. So object storage is definitely something that we think is a good way
 to go and you should do that. Object storage is not something for us that's out for in the future,
 right? We already have built quite a lot of work, and actually, like Moritz said before,
 like parallelize everything also applies to the networks, right? If you want to get the most out
 of the network bandwidth that you pay for with cloud instances in AWS and Azure and so on,
 you need to also fetch your data in parallel and be kind of chief, like reading at instance bandwidth
 from object storage to keep this delay of not having it available on SSD as low as possible
 and still get the most performance, even if your data is stored remotely.
 But I think the ability to run everything with SQL on a single node is probably everyone's stream
 to be honest, right? Who wants really wants to run thousands of servers? But I kind of
 thanks the question really like, how far are you guys right now? Because I'm sure everybody
 let's listening to this, and even like, got it in clean, like this could be really great.
 We'll probably want to try it, figure out can I use it? Are you ready for production yet,
 or where are you with the progress cedar DB? And if there's a way for people to actually want to
 wait with things, is it possible today or?
 So we are a very young company, we just incorporated this year. But we are, I mean,
 as you mentioned, we have now regular blog posts where you can get insights into what
 we are doing, what our technology does. And we also have a waitlist for interested potential
 customers. And so if you're interested in working with us, just sign up on our waitlist and you can
 join the few people that are already trying out and testing cedar DB for their production use case.
 And then of course, you can expect many more updates from us in the next months.
 That's amazing. So I guess to kind of top that off, where should it go find you? What is the best
 place to kind of like, key track of the progress of cedar DB here?
 So you can definitely find us on our website cedar DB.com, our blog posts are published there,
 and you can also find our Twitter account. And on LinkedIn, we will also publish our updates.
 So these are the three main channels.
 Amazing. I think this is one of those super exciting projects that
 hopefully becomes a product that everybody can certainly use. And it just changes the landscape,
 right? Thanks for both of you being on. We got enough high spiciness and all the sort of goodness
 that we need to get here. So everybody else, check out cedar DB, go download when they're ready,
 or track their progress. It's super exciting to hear this.
 Yeah, thank you very much for having us. Thank you. It's been so much fun.
