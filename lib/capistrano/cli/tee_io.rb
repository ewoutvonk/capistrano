require 'stringio'
class TeeIO
  attr_accessor :old_io
  attr_accessor :pipe_io
  attr_accessor :teed_io_name
  attr_accessor :auto_close_pipe_io
  attr_accessor :tee_on

  class << self

    def tee_all(pipe_io = nil, &block)
      if block_given?
        tee("$stdout", pipe_io) do |io|
          tee("$stderr", io) do
            yield
          end
        end
      else
        io = tee("$stdout", pipe_io)
        tee("$stderr", io)
      end
    end
    
    def tee_all_on
      $stderr.tee_on = true if $stderr.is_a?(TeeIO)
      $stdout.tee_on = true if $stdout.is_a?(TeeIO)
    end

    def tee_all_off
      $stderr.tee_on = false if $stderr.is_a?(TeeIO)
      $stdout.tee_on = false if $stdout.is_a?(TeeIO)
    end

    def tee(teed_io_name, pipe_io = nil, &block)
      eval("#{teed_io_name} = self.new(teed_io_name, pipe_io || StringIO.new, pipe_io.nil?)")
      if block_given?
        yield(eval("#{teed_io_name}.pipe_io"))
        eval("#{teed_io_name}.output")
      else
        eval("#{teed_io_name}.pipe_io")        
      end
    end

    def output_all
      $stderr.output if $stderr.is_a?(TeeIO)
      $stdout.output if $stdout.is_a?(TeeIO)
    end

  end

  def initialize(*args)
    @teed_io_name = args[0]
    @old_io = eval(args[0])
    @pipe_io = args[1]
    @auto_close_pipe_io = args[2]
    @tee_on = true
  end

  def call_on_io(method_name, *args, &block)
    call_on_old_io(method_name, *args, &block)
    call_on_pipe_io(method_name, *args, &block) if @tee_on
  end

  def call_on_old_io(method_name, *args, &block)
    if @old_io.is_a?(IO) || @old_io.is_a?(StringIO)
      @old_io.send(method_name, *args, &block)
      @old_io.flush
    end
  end

  def call_on_pipe_io(method_name, *args, &block)
    if @pipe_io.is_a?(IO) || @pipe_io.is_a?(StringIO)
      @pipe_io.send(method_name, *args, &block)
      @pipe_io.flush
    end
  end

  def puts(*args)
    call_on_io(:puts, *args)
  end

  def write(str)
    call_on_io(:write, str)
  end

  def method_missing(method_name, *args, &block)
    call_on_io(method_name, *args, &block)
  end

  def output
    reset_io
    if @auto_close_pipe_io && @pipe_io.is_a?(StringIO)
      str = @pipe_io.string
      @pipe_io.close
      str
    else
      @pipe_io
    end
  end

  def reset_io
    eval("#{teed_io_name} = @old_io")
  end
end
