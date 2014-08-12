module TestFlow
  extend Taskinator::Definition

  define_process do
    task :error_task, :continue_on_error => true

    task :the_task

    for_each :iterator do
      task :the_task
    end

    sequential do
      task :the_task
      task :the_task
      task :the_task
    end

    task :the_task

    concurrent do
      20.times do |i|
        task :the_task
      end
      task :the_task
    end

    task :the_task

    # invoke the specified sub process
    sub_process TestSubFlow
  end

  def error_task(*args)
    raise "It's a huge problem!"
  end

  # note: arg1 and arg2 are passed in all the way from the
  #  definition#create_process method
  def iterator(arg1, arg2)
    3.times do |i|
      yield [arg1, arg2, i]
    end
  end

  def the_task(*args)
    t = rand(1..11)
    Taskinator.logger.info "Executing task '#{task}' with [#{args}] for #{t} secs..."
    sleep 1 # 1
  end

  module TestSubFlow
    extend Taskinator::Definition

    define_process do
      task :the_task
      task :the_task
      task :the_task
    end

    def the_task(*args)
      t = rand(1..11)
      Taskinator.logger.info "Executing sub task '#{task}' with [#{args}] for #{t} secs..."
      sleep 1 # t
    end
  end

end
