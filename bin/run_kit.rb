# Shared runtime helpers for text/csv/json IO, shell cmds, banners, etc. Zero deps.
# note: instance methods will be private due to module_function

require "csv"
require "digest"
require "json"
require "open3"
require "pathname"
require "shellwords"
require "zlib"

module RunKit
  module_function

  #
  # file read/write, including gz
  #

  def file_read(path)
    Pathname(path).then do |path|
      data = path.read
      data = gunzip(data) if path.extname == ".gz"
      data
    end
  end

  def file_write(path, str)
    path = Pathname(path)
    atomic_write(path) do |tmp|
      str = gzip(str) if path.extname == ".gz"
      tmp.write(str)
    end
  end

  #
  # json file read/write, including gz
  #

  def json_read(path, symbolize_names: true) = JSON.parse(file_read(path), symbolize_names:)
  def json_write(path, json) = file_write(path, JSON.pretty_generate(json))
  def jsonl_read(path, symbolize_names: true) = file_read(path).split("\n").map { JSON.parse(_1, symbolize_names:) }
  def jsonl_write(path, json) = file_write(path, json.map { JSON.generate(_1) }.join("\n"))

  #
  # gzip/gunzip data
  #

  def gzip(str)
    Zlib::GzipWriter.new(StringIO.new).tap do
      _1.write(str)
    end.close.string
  end

  def gunzip(str_gz)
    gz = Zlib::GzipReader.new(StringIO.new(str_gz))
    gz.read
  ensure
    gz&.close
  end

  #
  # CSV read/write
  #

  def csv_read(path, infer: false)
    io = StringIO.new(file_read(path))
    rows = CSV.read(io, encoding: "bom|utf-8")

    headers = rows.shift.map(&:to_sym)
    klass = Struct.new(*headers)

    rows.map do |row|
      row = row.map { _infer_csv(_1) } if infer
      klass.new(*row)
    end
  end

  def csv_write(path, rows, headers: nil)
    atomic_write(path) do |tmp|
      CSV.open(tmp, "wb") { _csv_write0(_1, rows, headers:) }
    end
  end

  def csv_write_stdout(rows, headers: nil)
    CSV($stdout) { _csv_write0(_1, rows, headers:) }
  end

  #
  # shell/shell!
  #

  # Run a command via Open3.capture2e. `cmd` can be passed as:
  #
  # - shell("git status")      # a single string
  # - shell("git", "status")   # varargs strings
  # - shell(["git", "status"]) # an array of strings
  #
  # Prefer arrays so escaping stays explicit and Ruby handles argument
  # boundaries for you. Single strings are convenient but put escaping
  # responsibility on the caller. `vars:` lets you interpolate `{{ hi }}` into
  # the command before it runs. `Pathname` values get shell-escaped, which is
  # real nice here.
  #
  # Returns `[stdout_and_stderr, exit_code]`
  def shell(*cmd, vars: nil)
    output, status, _ = _shell(*cmd, vars:)
    [output, status]
  end

  # like shell, but raises on non zero exit code. returns stdout_and_stderr otherwise
  def shell!(*cmd, vars: nil)
    output, status, cmd = _shell(*cmd, vars:)
    raise "#{cmd.inspect} failed #{status}\noutput: #{output}" if status != 0
    output
  end

  # atomically transform file from src to dst
  def shell_transform!(*cmd, src:, dst:, force: false)
    src, dst = Pathname(src), Pathname(dst)
    tmp = dst.dirname.join(".tmp#{dst.extname}")
    tmp.unlink if tmp.exist?
    shell!(*cmd, vars: {src:, dst: tmp})
    cp_metadata(src, tmp)
    src.rename("old-#{src}") if src == dst
    dst.unlink if dst.exist? && force
    tmp.rename(dst)
    dst
  ensure
    tmp&.rmtree
  end

  # copy mtime and perms from src => dst
  def cp_metadata(src, dst)
    src, dst = Pathname(src), Pathname(dst)
    stat = src.stat
    dst.chmod(stat.mode)
    dst.chown(stat.uid, stat.gid)
    FileUtils.touch(dst, mtime: stat.mtime)
  end

  # Kill a process, ignore failure
  def kill_process(pid)
    Process.kill("KILL", pid)
  rescue Errno::ESRCH
  end

  # one-liners
  def glob(pats) = Pathname.glob(pats).uniq.sort
  def installed?(cmd) = shell("sh", "-c", "command -v #{cmd.shellescape}")[1] == 0
  def lines_in_file(path) = shell!("wc", "-l", path).strip.split.first.to_i
  def md5(str) = Digest::MD5.hexdigest(str)
  def program_name = Pathname($PROGRAM_NAME).basename
  def sha256(str) = Digest::SHA256.hexdigest(str)

  #
  # banner/warning/fatal
  #

  GREEN = "\e[1;38;5;231;48;2;64;160;43m"
  YELLOW = "\e[1;38;5;231;48;2;251;100;11m"
  RED = "\e[1;38;5;231;48;2;210;15;57m"
  RESET = "\e[0m"

  def banner(str, color: GREEN)
    puts "#{color}[#{_now.strftime("%H:%M:%S")}] #{str.ljust(72)} #{RESET}"
  end

  def warning(str)
    banner(str, color: YELLOW)
  end

  def fatal(str)
    banner(str, color: RED)
    raise SystemExit.new(1)
  end

  # Ask the user a question via stderr, then return true if they enter YES, yes, y, etc.
  def prompt?(prompt = "Proceed?")
    $stderr.write("#{prompt} (y/n) ")
    $stderr.flush
    ch = $stdin.gets || "no"
    ch.match?(/^y/i)
  end

  # Fetches data from `cache` file. If there is data in the cache with the given key, then that data is returned.
  def cache_fetch(cache:, compress: false, expires_in: nil, force: false, format: :json, symbolize: true, &)
    cache = Pathname(cache)
    stale = expires_in && (_now - cache.mtime > expires_in.to_i)
    data = if !cache.exist? || stale || force
      _cache_write(cache:, compress:, expires_in:, format:, &)
    else
      _cache_read(cache:, compress:, expires_in:, format:)
    end
    data = _symbolize_keys(data) if symbolize
    data
  end

  #
  # helpers
  #

  # Atomically replace a file by writing to a temporary path first.
  def atomic_write(path, &block)
    tmp = nil
    Pathname(path).tap do |path|
      path.dirname.mkpath
      tmp = Pathname("#{path}.tmp").tap { _1.unlink if _1.exist? }
      yield(tmp)
      tmp.rename(path)
    end
  ensure
    tmp.unlink if tmp&.exist?
  end

  # low-level helper for writing csv <= rows w/ headers
  def _csv_write0(csv, rows, headers: nil)
    headers ||= rows.first.to_h.keys
    csv << headers
    rows.each do |row|
      row = row.to_h
      csv << headers.map { row[_1] }
    end
  end

  # infer int/float from str
  def _infer_csv(str)
    case str
    when /\A-?\d+\z/ then return str.to_i
    when /\A-?\d+[.\d]+\z/ then return str.to_f
    end
    str
  end

  # shell helper
  def _shell(*cmd, vars: nil)
    begin
      cmd = _shell_cmd(cmd, vars:)
      output, status = Open3.capture2e(*cmd)
      status = status.exitstatus
    rescue Errno::ENOENT => ex
      output, status = ex.message, 127
    end
    [output.strip, status, cmd]
  end

  def _shell_cmd(cmd, vars: nil)
    cmd = cmd.first if cmd.one? && (cmd.first.is_a?(Array) || cmd.first.is_a?(String))
    if vars
      raise ArgumentError, "cmd must be string with vars: {...}" if !cmd.is_a?(String)
      cmd = vars.reduce(cmd) do |memo, (k, v)|
        k = "{{#{k}}}"
        raise ArgumentError, "#{cmd.inspect} does not contain #{k}" if !memo.include?(k)

        v = case v
        when Array then v.shelljoin
        when Pathname then v.to_s.shellescape
        else; v.to_s
        end
        memo.gsub(k, v)
      end
    end
    Array(cmd).map(&:to_s)
  end

  def _cache_read(cache:, compress: false, expires_in: nil, format: :json)
    data = cache.binread
    data = gunzip(data) if compress
    case format
    when :bin then data.force_encoding("ascii-8bit")
    when :json then JSON.parse(data)
    when :jsonl then data.split("\n").map { JSON.parse(_1) }
    when :marshal then Marshal.load(data)
    when :str, :string then data.force_encoding("utf-8")
    else; raise "unknown format #{format.inspect}"
    end
  end

  def _cache_write(cache:, compress: false, expires_in: nil, format: :json, &)
    yield.tap do
      data = case format
      when :bin, :str, :string then _1.to_s
      when :json then _1.to_json
      when :jsonl then _1.map(&:to_json).join("\n")
      when :marshal then Marshal.dump(_1)
      else; raise "unknown format #{format.inspect}"
      end
      data = gzip(data) if compress
      cache.binwrite(data)
    end
  end

  # note: no activesupport dependency
  def _symbolize_keys(obj)
    case obj
    when Hash
      obj.to_h do |k, v|
        k = begin
          k.to_sym
        rescue
          k
        end
        [k, _symbolize_keys(v)]
      end
    when Array then obj.map { _symbolize_keys(_1) }
    else; obj
    end
  end

  # we don't want activesupport, force getlocal
  def _now = Time.now.getlocal
end
