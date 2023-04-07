require 'optionparser'

# localでしか使わないので本体側もwritable
class DbCore
  def readonly?
    false
  end
end

class EdiCli
  def option
    @option ||= {}
  end

  def option_parser
    OptionParser.new do |opt|
      opt.on("-s id", "--send_client id",    "発注会社ID",     Integer) { |v| option[:send_client_id] = v }
      opt.on("-r id", "--receive_client id", "受注会社ID",     Integer) { |v| option[:receive_client_id] = v }
      opt.on("-c id", "--contract id",       "取引先ID",       Integer) { |v| option[:contract_id] = v }
      opt.on("-S id", "--send_user id",      "発注ユーザーID", Integer) { |v| option[:send_user_id] = v }
      opt.on("-R id", "--receive_user id",   "受注ユーザーID", Integer) { |v| option[:receive_user_id] = v }
      opt.on("-F id", "--foreman_user id",   "現場監督ID",     Integer) { |v| option[:foreman_user_id] = v }
      opt.on("-f",    "--force"              "確認不要",              ) { |v| option[:force_commit] = v }
    end
  end

  # ファイル一覧
  def command_files
    Dir.glob('bin/edi_cli/commands/*.rb')
  end

  # コマンド一覧（ignore? == true は除外)
  def command_classes
    @command_classes ||= command_files.map do |command_file|
      ['edi_cli', 'commands', File.basename(command_file, '.rb')].join('/').classify.safe_constantize
    end.reject do |command|
      command.ignore?
    end
  end

  # 番号で選択できるようコマンドに番号を振る
  def command_index
    @command_index ||= command_classes.each.with_object({}) do |command_class, h|
      description = command_class.description
      abort "同じ説明の機能があります: #{description}" if h.has_key?(description)
  
      h[(h.length + 1).to_s] = { description: description, command_class: command_class }
    end
  end
  
  # 初期化
  def initialize
    command_files.each { |command| load(command) } # コマンドをロード
  end

  # コマンド一覧表示
  def disp_commands
    command_index.each do |k, v|
      puts "#{k}: #{v[:description]}"
    end
  end

  # 開始
  def run!(num)
    puts 'BEGIN'
    (command_index[num][:command_class].option(option_parser, option) || option_parser).parse(ARGV.dup) # コマンド引数をパース
    command = command_index[num][:command_class].new(option)
    
    begin
      command.asks! # 機能と対話
    rescue => e
      puts e.message
    end
    
    DbCore.transaction do
      ApplicationRecord.transaction do
        begin
          command.execute! # 実行
        rescue => e
          puts e.message
          raise e
        end
        
        unless option[:force_commit]
          puts
          print 'commit?(yes/no): '
          res = STDIN.gets.chomp # yes or no
          raise unless ['yes', 'y'].include?(res.downcase)
        end
        puts 'COMMIT'
      end
    end
  rescue => e
    puts 'ROLLBACK'
  end
end

cli = EdiCli.new   # 機能のロード
cli.disp_commands # 機能の一覧表示

begin
  print "1-#{cli.command_index.count}: "
  num = STDIN.gets.chomp # 選択された番号
  
  raise unless cli.command_index.has_key?(num)

  cli.run!(num)
rescue
  retry if (@count = (@count.to_i + 1)) < 3

  abort "選択した番号が不正"
end
