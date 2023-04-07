module EdiCli::Commands
  class Order < Base
    attr_accessor :order_id, :contract_setting_id, :contract_order_type, :name, :delivery_address, :started_date, :worked_date, :use_template, :template_id

    def self.description
      '発注作成'
    end

    def self.option(parser, option)
      parser.on('--foo id', 'foo') { |v| option[:foo] = v }
    end

    def topics
      [
        { name: :order_id,            inquiry: '案件ID',                 type: :int },
        { name: :contract_setting_id, inquiry: '取引設定ID',             type: :int },
        { name: :contract_order_type, inquiry: '発注種別',               type: :int,    default: :engineering },
        { name: :name,                inquiry: '発注名',                 type: :string, default: Faker::Games::Pokemon.name },
        { name: :delivery_address,    inquiry: '納品先住所',             type: :string },
        { name: :started_date,        inquiry: '工程開始日',             type: :date,   default: Time.zone.today },
        { name: :worked_date,         inquiry: '工程終了日',             type: :date,   default: Time.zone.today },
        { name: :use_template,        inquiry: '明細テンプレートを使用', type: :string, default: :yes, choices: [:yes, :yes, :no, :no] },
        { name: :template_id,         inquiry: '明細テンプレートを選択', type: :int,    condition: -> (topic){ use_template == :yes } },
      ]
    end

    def default_order_id(_)
      ::Order.find_by(client_id: send_client_id).id
    end

    def default_contract_id(_)
      Contract.find_by(client_id: send_client_id, to_id: receive_client_id).id
    end

    def default_contract_setting_id(_)
      ContractSetting.find_by(contract_id: contract_id).id
    end

    def default_delivery_address(_)
      ::Order.find(order_id).property.view_full_address || '住所不定'
    end

    def default_template_id(_)
      TemplateContractEstimate.find_by(send_client_id:, contract_order_type:).id
    end

    def choice_order_id(_)
      ::Order.where(client_id: send_client_id).pluck(:site_name, :id).map do |name, id|
        ["#{name}(#{id})", id]
      end.flatten
    end

    def choice_contract_order_type(_)
      ContractOrder.contract_order_types.symbolize_keys.each.with_object({}) {|(k,v),h| h[k] = k }.to_a.flatten
    end

    def choice_contract_setting_id(_)
      ContractSetting.where(send_client_id:, contract_id:).pluck(:name, :id).map do |name, id|
        ["#{name}(#{id})", id]
      end.flatten
    end

    def choice_template_id(_)
      TemplateContractEstimate.where(send_client_id:, contract_order_type:).pluck(:name, :id).map do |name, id|
        ["#{name}(#{id})", id]
      end.flatten
    end

    def execute!
      contract_order.set_price
      contract_order.save!
    end

    def contract_order
      @contract_order ||= ContractOrder.new(
        send_client_id:, receive_client_id:, contract_id:, contract_setting_id:, send_user_id:, receive_user_id:, foreman_user_id:,
        order_id:, contract_order_type:, name:, delivery_address:, started_date:, worked_date:, contract_order_items:)
    end

    def contract_order_items
      @items ||= TemplateContractEstimate.find(template_id).child_items.map do |item|
        ContractOrderItem.new(item.attributes.except(*reject_params))
      end
    end

    def reject_params
      %w[id template_contract_estimate_id created_at updated_at]
    end
  end
end
