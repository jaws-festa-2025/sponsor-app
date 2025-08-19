class Admin::ConferencesController < Admin::ApplicationController
  TAX_RATE = 0.1

  before_action :require_unrestricted_staff, only: [:index, :new, :create]
  before_action :set_conference, only: [:show, :edit, :update, :destroy, :attendees_keeper, :sponsors_yml, :sponsors_json, :asset_urls, :table_view, :billing]

  def index
    @conferences = Conference.all
  end

  def show
    @plans_with_count = @conference
      .plans
      .left_joins(:sponsorships)
      .group(:id)
      .select('plans.*, COUNT(sponsorships.plan_id) as cnt')
      .map {|_| [_, _.cnt, _.capacity] }
      .sort_by { |plan, _cnt, _capa| -plan.rank }
  end

  def attendees_keeper
  end

  def sponsors_yml
    render plain: GenerateSponsorsYamlFileJob.new(@conference, push: false, preview: params[:preview].to_s == 'true').tap(&:perform_now).yaml_data
  end

  def sponsors_json
    render plain: GenerateSponsorsYamlFileJob.new(@conference, push: false, preview: params[:preview].to_s == 'true').tap(&:perform_now).json_data
  end

  def table_view
    @sponsorships = @conference.sponsorships
      .includes_contacts
      .includes_requests
  end

  def asset_urls
    render json: {
      files: @conference.sponsorships.includes(:asset_file).map(&:asset_file).compact.map do |asset|
        [asset.filename, asset.download_url]
      end,
    }.to_json
  end

  # https://biz.moneyforward.com/support/invoice/faq/invoice/invoice002.html
  def billing
    @billings = []

    @billings << %w[csv_type(変更不可) 行形式 取引先名称 件名 請求日 お支払期限 請求書番号 売上計上日 メモ タグ 小計 消費税 合計金額 取引先敬称 取引先郵便番号 取引先都道府県 取引先住所1 取引先住所2 取引先部署 取引先担当者役職 取引先担当者氏名 自社担当者氏名 備考 振込先 入金ステータス メール送信ステータス 郵送ステータス ダウンロードステータス 納品日 品名 品目コード 単価 数量 単位 納品書番号 詳細 金額 品目消費税率]

    billing_day = params[:billing_day] ? Date.parse(params[:billing_day]) : Date.today
    booth_price = params[:booth_price].to_i

    sponsorships = @conference.sponsorships.active.includes_contacts.includes(:plan).order(:plan_id, :id)

    sponsorships.each.with_index(1) do |sponsor, i|
      subtotal = sponsor.plan.price
      subtotal += booth_price if sponsor.booth_assigned
      tax = (subtotal * TAX_RATE).to_i

      @billings << [40101, '請求書', sponsor.billing_contact.organization, "#{@conference.name} 協賛のご請求", billing_day.strftime('%Y/%m/%d'), (billing_day + 1.month).end_of_month.strftime('%Y/%m/%d'),"#{billing_day.strftime("%Y%m%d")}-#{format("%03<number>d", number: i)}", billing_day.strftime('%Y/%m/%d'), sponsor.plan.name,  nil, subtotal, tax, subtotal + tax, sponsor.billing_contact.organization, nil, sponsor.billing_contact.address, nil, nil, sponsor.billing_contact.unit, '', sponsor.billing_contact.name, nil, '払込手数料は、御社のご負担とさせていただきます。'] + Array.new(12)

      @billings << [40101, '品目'] + Array.new(27) + ["#{@conference.name} 協賛費用 (#{sponsor.plan.name})", nil, sponsor.plan.price, 1, nil, nil, nil, sponsor.plan.price, '10%']

      if sponsor.booth_assigned
        @billings << [40101, '品目'] + Array.new(27) + ["#{@conference.name} 協賛費用 (ブース出展)", nil, booth_price, 1, nil, nil, nil, booth_price, '10%']
      end
    end

    respond_to do |format|
      format.html do
        render :billing
      end
      format.csv do
        billing_csv = CSV.generate(row_sep: "\r\n") do |csv|
          @billings.each do |billing|
            csv << billing
          end
        end

        send_data(billing_csv, filename: "#{@conference.name.underscore.gsub(' ', '_')}_billing.csv")
      end
    end
  end

  def new
    @conference = Conference.new
  end

  def edit
  end

  def create
    @conference = Conference.new(conference_params)

    respond_to do |format|
      if @conference.save
        format.html { redirect_to @conference, notice: 'Conference was successfully created.' }
      else
        format.html { render :new }
      end
    end
  end

  def update
    @conference.assign_attributes(conference_params)
    @conference.allow_restricted_access = true if current_staff.restricted_repos
    respond_to do |format|
      if @conference.save
        format.html { redirect_to @conference, notice: 'Conference was successfully updated.' }
      else
        format.html { render :edit }
      end
    end
  end

  def destroy
    @conference.destroy
    respond_to do |format|
      format.html { redirect_to _conferences_url, notice: 'Conference was successfully destroyed.' }
    end
  end

  private

  def set_conference
    @conference = Conference.find_by!(slug: params[:slug])
    check_staff_conference_authorization!(@conference)
  end

  def conference_params
    params.require(:conference).permit(
      :name,
      :slug,
      :application_opens_at,
      :application_closes_at,
      :ticket_distribution_starts_at,
      :amendment_closes_at,
      :booth_capacity,
      :contact_email_address,
      :additional_attendees_registration_open,
      :github_repo,
      :tito_slug,
      :hidden,
      :no_plan_allowed,
      :allow_restricted_access,
      :commercial_message_movie_capacity,
    )
  end
end
