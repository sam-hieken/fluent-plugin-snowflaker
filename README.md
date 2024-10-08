# Snowflaker

This filter plugin allows you to generate Twitter [Snowflake IDs](https://en.wikipedia.org/wiki/Snowflake_ID) and add them to your logs in Fluentd. 

## Disclaimer

I did not write the original code to generate Snowflake IDs; it's a slightly reworked version of @pmarreck's [Ruby Snowflake ID generator](https://gist.github.com/pmarreck/8049971). After throrough review and testing, I found no significant differences with it compared to [Twitter's Snowflake implementation](https://github.com/twitter-archive/snowflake/tree/snowflake-2010). 

### Snowflake ID Disclaimer

Information regarding Snowflake IDs is limited, not helped by the fact there are many different implementations based on the original (e.g. Instagram). This plugin uses the original Snowflake ID implementation [from Twitter](https://github.com/twitter-archive/snowflake/blob/snowflake-2010/src/main/scala/com/twitter/service/snowflake/IdWorker.scala), consisting of a timestamp (41 bits), worker ID (5 bits), datacenter ID (5 bits), and sequence number (12 bits).

### Issues and Changes

Since this is just a fluent plugin form of Twitter's Snowflake generator, I won't maintain to this repository outside of bug fixes. If you find any significant problems with the code, please submit a PR.

## Installation

**TODO**

## Configuration

### Parameters
- **column**: The key in your record to assign this ID to. Will overwrite any existing value. 
  - **Type**: *string*
  - **Default**: "id"
- **worker_id**: A 5-bit unique identifier for the machine, or "worker", generating this ID. 
  - **Type**: *int*
  - **Default**: 1
- **datacenter_id**: A 5-bit unique identifier for the datacenter this machine is in.
  - **Type**: *int*
  - **Default**: 1
- **custom_epoch_ms**: A custom epoch (milliseconds since the Unix epoch) to use as the basis for generating IDs. Cannot be greater than the current Unix millisecond time. I recommend setting this as high as is possible; however, ensure you don't change it after you begin generating IDs (otherwise they could collide on the same worker and datacenter).
  - **Type**: *int*
  - **Default**: 1288834974657 *(the "Twitter Epoch")*
- **sequence_start**: The custom sequence number to start generating IDs with. I highly recommend not setting this unless you're debugging.
  - **Type**: *int*
  - **Default**: 0

### Examples 

The following configuration:

```
<source test>
  @type sample
  sample {"hello":"world"}
  tag test
</source>

<filter test>
  @type snowflaker
  worker_id 7
  datacenter_id 1
  custom_epoch_ms 1420070400000
  column test_key
</filter>

<match test>
  @type stdout
</match>  
```

Will produce a similar output (IDs will vary based on the time generated): 

```
2024-10-07 21:17:47.002660310 -0400 test: {"hello":"world","test_key":1293019479286116352}
2024-10-07 21:17:48.007410121 -0400 test: {"hello":"world","test_key":1293019483501391872}
...
```

#### Example Filter With All Parameters Included

```
<filter test>
  @type snowflaker
  worker_id 2
  datacenter_id 4
  custom_epoch_ms 1728352090609
  column my_id
  sequence_start 1
</filter>
```

#### Overwriting

As mentioned above, if the key specified in `column` already has a value, it will simply be overwritten with the generated ID.

The following configuration:

```
<source test>
  @type sample
  sample {"hello":"world","id":"testing_123"}
  tag test
</source>

<filter test>
  @type snowflaker
  worker_id 7
  datacenter_id 1
  custom_epoch_ms 1420070400000
  column id
</filter>

<match test>
  @type stdout
</match>  
```

Will produce a similar output:

```
2024-10-07 21:17:47.002660310 -0400 test: {"hello":"world","test_key":1293019479286116352}
2024-10-07 21:17:48.007410121 -0400 test: {"hello":"world","test_key":1293019483501391872}
...
```

#### Anti-Pattern: Multiple Filters

Currently, if you use multiple filters, **ensure they do NOT use the same worker_id and datacenter_id!!!** Each filter contains its own instance of an ID generator, and will therefore not be able to deal with timestamp conflicts; in other words, your generated IDs could end up colliding. 

**WRONG:**
```
<filter my_tag>
  @type snowflaker
  worker_id 7
  datacenter_id 1
  column id
</filter>

<filter my_other_tag>
  @type snowflaker
  worker_id 7
  datacenter_id 1
  column other_id
</filter>
```

I wouldn't recommend using multiple filters, but if you must, change the `worker_id` to avoid collisions between generators:

**CORRECT:**
```
<filter my_tag>
  @type snowflaker
  worker_id 7
  datacenter_id 1
  column id
</filter>

<filter my_other_tag>
  @type snowflaker
  worker_id 6
  datacenter_id 1
  column other_id
</filter>
```

I'll likely push a fix to this in the future so that `<filter>`s will use the same ID generator instance if passed the same configuration parameters. Feel free to reach out if you're interested, but currently this is an anti-pattern.
