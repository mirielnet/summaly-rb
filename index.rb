require 'sinatra'
require 'faraday'
require 'oj'
require 'nokogiri'
require 'addressable/uri'

CONFIG = {
  bind_addr: '0.0.0.0:12267',
  timeout: 5000,
  user_agent: 'summaly-rb',
  max_size: 2 * 1024 * 1024,
  proxy: nil,
  media_proxy: nil,
  append_headers: [
    "Content-Security-Policy:default-src 'none'; img-src 'self'; media-src 'self'; style-src 'unsafe-inline'",
    "Access-Control-Allow-Origin:*"
  ]
}

helpers do
  def fetch_content(url, user_agent, lang, timeout)
    conn = Faraday.new(url: url) do |faraday|
      faraday.headers['User-Agent'] = user_agent
      faraday.headers['Accept-Language'] = lang if lang
      faraday.options.timeout = timeout / 1000.0
    end
    response = conn.get
    if response.success?
      response.body
    else
      halt 500, { 'X-Proxy-Error' => response.status.to_s }, "Failed to fetch content"
    end
  end

  def parse_html(content)
    Nokogiri::HTML(content)
  end

  def build_summaly_result(doc, base_url, config)
    result = {
      url: base_url.to_s,
      title: nil,
      icon: nil,
      description: nil,
      thumbnail: nil,
      sitename: nil,
      player: {},
      sensitive: false,
      activity_pub: nil,
      oembed: nil
    }

    doc.css('meta').each do |meta|
      case meta['property']
      when 'og:image'
        result[:thumbnail] = meta['content']
      when 'og:url'
        result[:url] = meta['content']
      when 'og:title'
        result[:title] = meta['content']
      when 'og:description', 'description'
        result[:description] = meta['content']
      when 'og:site_name'
        result[:sitename] = meta['content']
      end
    end

    doc.css('title').each do |title|
      result[:title] ||= title.text
    end

    result
  end
end

get '/' do
  url = params['url']
  lang = params['lang']
  user_agent = params['userAgent'] || CONFIG[:user_agent]
  timeout = [CONFIG[:timeout], (params['responseTimeout'] || CONFIG[:timeout]).to_i].min

  if url.start_with?('coffee://')
    headers 'X-Proxy-Error' => "I'm a teapot"
    status 418
    body ''
  else
    content = fetch_content(url, user_agent, lang, timeout)
    doc = parse_html(content)
    base_url = Addressable::URI.parse(url)
    result = build_summaly_result(doc, base_url, CONFIG)

    content_type :json
    Oj.dump(result)
  end
end

not_found do
  'Not found'
end

error do
  'Error'
end

# Sinatraアプリケーションを実行するためのコード
if __FILE__ == $0
  set :bind, '0.0.0.0'
  set :port, 12267
end
