require 'nokogiri'

x = Nokogiri::XML($stdin.read)

parts = x.xpath('//export/components/comp').map do |n|
  {
    count: '',
    value: n.xpath('value/text()').to_s,
    footprint: n.xpath('substring-after(footprint/text(), ":")').to_s,
    bom: n.xpath('fields/field[@name="BOM"]/text()').to_s,
    place: n.xpath('fields/field[@name="Place"]/text()').to_s,
    ref: n.xpath('@ref').to_s,
  }
end

parts.select!{|p| !['np', 'nopart'].include?p[:place].downcase }

grouped = parts.group_by {|n| [n[:footprint], n[:bom], n[:value], n[:place]]}.values

res = grouped.map do |group|
  namedpart = group.first.dup
  refs = group.map{|n| n[:ref]}
  namedpart[:ref] = refs.join(" ")
  namedpart[:count] = refs.count
  namedpart
end

restab = [res.first.keys]
restab += res.map{|n| n.values}

resstr = restab.map{|line| line.join("\t")}.join("\n")

$stdout.puts resstr
