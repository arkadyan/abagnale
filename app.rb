require 'rubygems'
require 'sinatra'
require 'pry'
require 'pg'
require 'active_record'
require 'nokogiri'
require 'logger'

logger = Logger.new(STDOUT)

ActiveRecord::Base.establish_connection(
   :adapter => 'postgresql',
   :database =>  'abagnale'
)
# ActiveRecord::Base.logger = Logger.new(STDOUT)

require './cc'
require './transaction'

get '/hi' do
  "Hello World\n"
end

# Chase Paymentech Orbital
post '/authorize' do
  xml = request.body.read
  begin
    doc =  Nokogiri::XML(xml)
    case (request_name = doc.xpath('/Request/*').first.name)
    when "NewOrder"
      fullccnum = doc.xpath('//AccountNum').inner_text
      name = doc.xpath('//AVSname').inner_text
      order = doc.xpath('//OrderID').inner_text
      amount = doc.xpath('//Amount').inner_text

      result = Cc.result(fullccnum)
      tx = Transaction.create!(:fullccnum => fullccnum, :name => name, :auth_result => result, :order => order, :amount => amount)
      body = File.read(File.dirname(__FILE__) + "/fixtures/orbital/auth_#{result}.xml")
      body.gsub!(/BADFOODDEADBEEFDECAFBAD1234567890FEDBOOD/, "abagnale-#{tx.id}")
    when "MarkForCapture"
      txrefnum = doc.xpath('//TxRefNum').inner_text
      tx_id = txrefnum.split('-').last
      Transaction.find(tx_id).update_attributes(:settled_at => Time.now)
      body = File.read(File.dirname(__FILE__) + "/fixtures/orbital/capture_success.xml")
    else
      logger.warn("Unrecognized orbital request #{request_name}")
    end
    headers "Content-Type" => 'application/xml'
    body
  rescue => err
    logger.warn("Bogus orbital request: #{err}")
    halt 400, "What's the matter with you?"
  end
end

# Litle
post '/vap/communicator/online' do
  xml = request.body.read
  begin
    doc =  Nokogiri::XML(xml)
    ns = doc.children.first.namespace.href # dumbass xml namespaces

    case (request_name = doc.xpath("//ns:litleOnlineRequest/*", 'ns' => ns).last.name)
    when "authorization"
      fullccnum = doc.xpath('//ns:card/ns:number', 'ns' => ns).inner_text
      name = doc.xpath('//ns:name', 'ns' => ns).inner_text
      order = doc.xpath('//ns:orderId', 'ns' => ns).inner_text
      amount = doc.xpath('//ns:amount', 'ns' => ns).inner_text

      result = Cc.result(fullccnum)
      tx = Transaction.create!(:fullccnum => fullccnum, :name => name, :auth_result => result, :order => order, :amount => amount)
      body = File.read(File.dirname(__FILE__) + "/fixtures/litle/auth_#{result}.xml")
      body.gsub!(/BADFOODDEADBEEFDECAF/, "abagnale-#{tx.id}")
    when "capture"
      txrefnum = doc.xpath('//ns:litleTxnId', 'ns' => ns).inner_text
      tx_id = txrefnum.split('-').last
      Transaction.find(tx_id).update_attributes(:settled_at => Time.now)
      body = File.read(File.dirname(__FILE__) + "/fixtures/litle/capture_success.xml")
    else
      logger.warn("Unrecognized litle request #{request_name}")
      halt 400, "What are you talking about?"
    end
    headers "Content-Type" => 'application/xml'
    body
  rescue => err
    logger.warn("Bogus orbital request: #{err}")
    halt 400, "What's the matter with you?"
  end
end