require "json"
require "http"
require "colorize"

struct Food
  alias Ingreediant = Hash(String, Int32)
  property name : String, cal : Int32
  property protein : Int32, carb : Int32, fat : Int32
  property protein_pct : Int32, carb_pct : Int32, fat_pct : Int32
  property ingredients : Array(Ingreediant)

  def initialize(@name, @ingredients)
    @cal = sum "calories"
    @protein = sum "protein"
    @carb = sum "carbohydrate"
    @fat = sum "fat"

    @protein_pct = ratio(protein, 4)
    @carb_pct = ratio(carb, 4)
    @fat_pct = ratio(fat, 9)
  end

  private def sum(key)
    ingredients.map(&.[key]?).compact.sum
  end

  private def ratio(m, s)
    (m * s * 100.0 / cal).to_i
  end
end

def agg(name, ingredients)
  ings = Array(Food::Ingreediant).new
  ingredients.each do |i|
    next if i.name.match(/sides inclu/i)
    next if i.name.match(/w\/ dressing/i)

    h = Hash(String, Int32).new
    i.nutrition.each do |n|
      h[n.name.downcase] = n.amount_in_unit
    end
    ings << h
  end

  Food.new(name: name, ingredients: ings)
end

def process(json)
  items = Array(Food).new
  json.items.not_nil!.values.each do |i|
    ni = i.nutrition_infos
    name = i.item
    if ni && ni.size > 0 && !(ni.size == 1 && ni.first.nutrition.empty?)
      items << agg(name, ni)
    end
  end
  items
end

module MacroConverter
  def self.from_json(value : JSON::PullParser) : Int32
    value.read_string.gsub(/\D/, "").to_i
  end
end

struct Nutrition
  JSON.mapping(name: String, amount_in_unit: {type: Int32, converter: MacroConverter})
end

struct NutritionInfo
  JSON.mapping(name: String, nutrition: Array(Nutrition))
end

struct Item
  JSON.mapping(item: String, nutrition_infos: Array(NutritionInfo)?)
end

struct Structure
  JSON.mapping(date: String, items: Hash(String, Item)?, closed: Bool?)
end

def dsp(raw)
  json = Structure.from_json(raw)
  return if json.closed
  puts "#{json.date.ljust(35)}\t cal\tpro/crb/fat\tpr/cb/ft pct"
  process(json).sort_by(&.cal).each do |i|
    name = i.name.[0, 35].ljust(35)
    cal = i.cal.to_s.rjust(4)
    macros = "#{i.protein.to_s.rjust(3)}/#{i.carb.to_s.rjust(3)}/#{i.fat.to_s.rjust(3)}"
    pct = "#{i.protein_pct.to_s.rjust(2)}/#{i.carb_pct.to_s.rjust(2)}/#{i.fat_pct.to_s.rjust(2)}"

    cal = cal.colorize(:light_green) if i.cal < 600
    pct = pct.colorize(:light_green) if i.protein_pct >= 30

    puts "#{name}\t#{cal}\t#{macros}\t#{pct}"
  end
  puts
  puts
end

def get_creds
  creds = `security find-generic-password -a ${USER} -s eatclub_creds -w`
  creds == "" ? set_pass : creds
end

def set_pass
  print "email: "
  email = gets.not_nil!.chomp
  print "password: "
  pass = gets.not_nil!.chomp

  creds = {email: email, password: pass}.to_json
  `security add-generic-password -a ${USER} -s eatclub_creds -w '#{creds}'`
  creds
end

headers = HTTP::Headers{"content-type" => "application/json;charset=UTF-8"}
login = HTTP::Client.put("https://www.eatclub.com/public/api/log-in/",
  body: get_creds,
  headers: headers
)

(1..5).each do |i|
  url = "https://www.eatclub.com/menus/?categorized_menu=true&day=#{i}&menu_type=individual"
  resp = HTTP::Client.get(url, headers: login.cookies.add_request_headers(headers))
  dsp(resp.body)
end
