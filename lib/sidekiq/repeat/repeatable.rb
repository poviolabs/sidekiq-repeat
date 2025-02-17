module Sidekiq
  module Repeat
    module Repeatable
      module ClassMethods
        def repeat(&block)
          @block = block
        end

        def cronline
          return @cronline if @cronline
          return if @block.nil?

          # Support for IceCube
          @cronline = IceCube::Schedule.new(Date.today.to_datetime)
          @cronline.add_recurrence_rule(IceCube::Rule.instance_eval(&@block))
          return @cronline

        rescue ArgumentError
          fail "repeat '#{@cronline}' in class #{self.name} is not a valid cron line"
        end

        def reschedule
          # Only if repeat is configured.
          return unless !!cronline

          ts   = cronline.next_occurrence
          args = []
          nj   = next_scheduled_job

          if nj
            if nj.at > ts
              nj.item['args'] = args
              nj.reschedule ts.to_f
              Sidekiq.logger.info "Re-scheduled #{self.name} for #{ts}."
            end
          else
            self.perform_at ts.to_f, *args
            Sidekiq.logger.info "Scheduled #{self.name} for #{ts}."
          end
        end

        def next_scheduled_job
          @ss ||= Sidekiq::ScheduledSet.new
          @ss.find { |job| job.klass == self.name }
        end
      end

      class << self
        def repeatables
          @repeatables ||= []
        end

        def reschedule_all
          repeatables.each(&:reschedule)
        end

        def included(klass)
          klass.extend(Sidekiq::Repeat::Repeatable::ClassMethods)
          repeatables << klass
        end
      end
    end
  end
end
