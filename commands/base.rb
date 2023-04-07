module Commands
  class Base
    def self.ignore?
      self == Base
    end
  
    def self.option(parser, option); end

    def initialize(attr)
      # コマンドライン引数を取得
      attr.each do |k, v|
        instance_variable_set("@#{k}", v)
      end
    end

    # コマンド実行に必要な対話リスト
    def topics
      []
    end

    # 質問リストを実行
    # 回答をセット
    def asks!(topics=nil)
      Topic.build(self, (topics ||= self.topics)).each do |topic|
        next if topic.condition && topic.condition.call(self) == false
        topic.ask!
        instance_variable_set("@#{topic.name}", topic.value)
      end
    end

    def execute!
      raise 'やりたいことを実装してね'
    end
  end

  class Topic
    class RequiredTopicError < StandardError; end
    include ActiveModel::Model

    # まとめて作成
    def self.build(command, inquiries)
      inquiries.map do |inquiry|
        new(command, inquiry)
      end
    end

    attr_accessor :inquiry, :type, :name, :nested, :choices, :condition, :required, :default
    attr_reader :value
    attr_reader :command

    def initialize(command, attr)
      @command = command
      super(attr)
    end

    # inquiryを標準入力で問いかける
    # choices がある場合は選択肢に番号を振って選択させる
    # ない場合は type にしたがって入力をコンバート
    # required == false で未入力なら default を設定
    # 不正な選択や必須項目の未入力はリトライ
    # リトライが３回以上でAbort
    def ask!
      count = 0
      begin
        val = gets
        raise RequiredTopicError.new if required && val.present? == false
        if choices
          val = choice(val)
        else
          val = convert(val)
        end
        val = set_default unless val.present?
        @value = val
        puts "  => #{val}"
        self
      rescue => e
        reason = '回答が不正'
        reason = '必須項目' if e.is_a?(RequiredTopicError)
        puts reason
        count += 1
        retry if count <= 5
        abort 'やめた'
      end
    end

    def set_default
      return default.call(self) if default.is_a?(Proc)
      command.try("default_#{name}", self) || default
    end

    def show_required
      return '*' if required
      ''
    end

    def choices
      # choicesは { label: foo, value: bar }, { label: hoge, value: fuga } と書いてもいいが
      # めんどくさいので [foo, bar hoge, fuga] でもいいようにしている
      
      return @arranged_choices if @arranged_choices

      arranged_choices
    end

    def arranged_choices
      @arranged_choices = @choices.each_slice(2).map do |slice|
        [:label, :value].zip(slice).to_h
      end if @choices.is_a?(Array)

      @arranged_choices ||= command.send("choice_#{name}", self).each_slice(2).map do |slice|
        [:label, :value].zip(slice).to_h
      end if command.respond_to?("choice_#{name}")

      @arranged_choices
    end

    def choice(val)
      return unless val.present?            # 空文字はデフォルト
      raise  unless val.match?(/^[0-9]+$/)  # 数字じゃなければエラー
      choices_map[val.to_i][:value]         # 範囲外の数字はエラー
    end

    def choices_map
      return {} unless choices
      @choices_map ||= choices.each.with_object({}) do |choice, h|
        h[h.size + 1] = choice
      end
    end

    def choice_menu
      choices_map.each.map do |k, v|
        "  #{k}:#{v[:label]}"
      end.join("\n")
    end

    def choice_num
      return nil unless choices_map.present?
      "(1-#{choices_map.count})"
    end

    def gets
      if choices
        puts "#{show_required}#{inquiry}: "
        puts choice_menu
        print "  #{choice_num}: "
      else
        print "#{show_required}#{inquiry} #{choice_num}: "
      end
      val = STDIN.gets.chomp
    end

    # 標準入力を文字列 -> 型変換
    def convert(val)
      return nil unless val.present?
      case type
      when :int
        val.to_i
      when :boolean
        ['true', 'yes'].include?(val.downcase)
      when :decimal
        val.to_d
      when :date
        val.to_date
      when :time
        val.to_datetime
      else
        val
      end
    end
  end
end
