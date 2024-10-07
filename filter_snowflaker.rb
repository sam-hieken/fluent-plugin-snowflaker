#
# 2024 - Sam Hieken
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'fluent/plugin/filter'
require 'monitor'

module Fluent
  module Plugin
    class SnowflakerFilter < Fluent::Plugin::Filter
      Fluent::Plugin.register_filter("snowflaker", self)
      # The machine ID. 5 bits max.
      config_param :worker_id, :integer, default: 1
      # The data center ID. 5 bits max.
      config_param :datacenter_id, :integer, default: 1
      # The starting sequence for generating IDs.
      config_param :sequence_start, :integer, default: 0

      # The custom epoch in milliseconds to use as the base epoch for generating IDs. Defaults to
      # the "Twitter Epoch" (1288834974657). Recommended to set this to the time you first begin
      # persisting data (or as close as possible) if data will be persisted far into the future.
      config_param :custom_epoch_ms, :integer, default: 1288834974657 #1420070400000
      # The record property to generate this ID into. Defaults to "id".
      config_param :column, :string, default: "id"

      class IdWorker
        attr_reader :worker_id, :datacenter_id, :logger, :sequence, :last_timestamp, :custom_epoch

        TWEPOCH = 1288834974657
        WORKER_ID_BITS = 5
        DATACENTER_ID_BITS = 5
        MAX_WORKER_ID = (1 << WORKER_ID_BITS) - 1
        MAX_DATACENTER_ID = (1 << DATACENTER_ID_BITS) - 1
        SEQUENCE_BITS = 12
        WORKER_ID_SHIFT = SEQUENCE_BITS
        DATACENTER_ID_SHIFT = SEQUENCE_BITS + WORKER_ID_BITS
        TIMESTAMP_LEFT_SHIFT = SEQUENCE_BITS + WORKER_ID_BITS + DATACENTER_ID_BITS
        SEQUENCE_MASK = (1 << SEQUENCE_BITS) - 1

        # note: this is a class-level (global) lock.
        # May want to change to an instance-level lock if this is reworked to some kind of singleton or worker daemon.
        MUTEX_LOCK = Monitor.new

        def initialize(worker_id = 0, datacenter_id = 0, custom_epoch = TWEPOCH, sequence = 0, logger = nil)
          raise "Worker ID set to #{worker_id} which is invalid" if worker_id > MAX_WORKER_ID || worker_id < 0
          raise "Datacenter ID set to #{datacenter_id} which is invalid" if datacenter_id > MAX_DATACENTER_ID || datacenter_id < 0
          @worker_id = worker_id
          @datacenter_id = datacenter_id
          @sequence = sequence
          @custom_epoch = custom_epoch
          @logger = logger # || lambda{ |r| puts r }
          @last_timestamp = -1
          @logger.info("IdWorker starting. timestamp left shift %d, datacenter id bits %d, worker id bits %d, sequence bits %d, workerid %d" % [TIMESTAMP_LEFT_SHIFT, DATACENTER_ID_BITS, WORKER_ID_BITS, SEQUENCE_BITS, worker_id])
        end

        def get_id(*)
          # log stuff here, theoretically
          next_id
        end
        alias call get_id

        protected

        def next_id
          MUTEX_LOCK.synchronize do
            timestamp = current_time_millis
            if timestamp < @last_timestamp
              @logger.fatal("clock is moving backwards.  Rejecting requests until %d." % @last_timestamp)
            end
            if @last_timestamp == timestamp
              @sequence = (@sequence + 1) & SEQUENCE_MASK
              if @sequence == 0
                timestamp = till_next_millis(@last_timestamp)
              end
            else
              @sequence = 0
            end
            @last_timestamp = timestamp
            @logger.trace("Generating snowflake, timestamp=#{timestamp} datacenter_id=#{datacenter_id} worker_id=#{worker_id} sequence=#{@sequence}")
            ((timestamp - custom_epoch) << TIMESTAMP_LEFT_SHIFT) |
              (@datacenter_id << DATACENTER_ID_SHIFT) |
              (@worker_id << WORKER_ID_SHIFT) |
              @sequence
          end
        end

        private

        def current_time_millis
          (Time.now.to_f * 1000).to_i
          #1728330085185
        end

        def till_next_millis(last_timestamp = @last_timestamp)
          timestamp = nil
          # the scala version didn't have the sleep. Not sure if sleeping releases the mutex lock, more research required
          while (timestamp = current_time_millis) < last_timestamp; sleep 0.0001; end
          timestamp
        end

      end

      # Register this filter as "passthru"
      #Fluent::Plugin.register_filter('passthru', self)

      # config_param works like other plugins

      def configure(conf)
        super
        # Do the usual configuration here
      end

      def start
        super
        log.info "Initializing snowflaker with column=#{column} worker_id=#{worker_id} datacenter_id=#{datacenter_id} custom_epoch_ms=#{custom_epoch_ms}"
        @id_worker = IdWorker.new(@worker_id, @datacenter_id, @custom_epoch_ms, @sequence_start, log)
      end

      # def shutdown
      #   # Override this method to use it to free up resources, etc.
      #   super
      # end

      def filter(tag, time, record)
        # Generate Snowflake ID into @column based on config
        record[@column] = @id_worker.get_id
        record
      end
    end
  end
end

