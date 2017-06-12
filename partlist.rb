require 'nokogiri'
require 'optparse'

def print_csv(ary, dest)
  ary.map do |elems|
    l = elems.map do |e|
      if /["',\\]/ === e
        e = '"%s"'%e.gsub(/[\\"]/, '\\\1')
      end
      e
    end.join(",")
    dest.puts l
  end
end

def print_org(ary, dest)
  widths = ary.reduce([0]*ary.first.length) do |memo, elems|
    memo.zip(elems.map(&:to_s).map(&:length)).map(&:max)
  end
  align = ary[1..-1].reduce([true]*ary.first.length) do |memo, elems|
    memo.zip(elems.map(&:to_s).map{|e|/^[0-9.]*$/===e}).map(&:all?)
  end

  header = true
  ary.map do |elems|
    l = align.zip(widths, elems).map do |a|
      (a.first ? "%*s" : "%-*s") % a[1..-1]
    end.join(' | ')
    dest.puts "| #{l} |"
    if header
      header = false
      dest.puts '+%s+' % widths.map{|w| '-'*(w+2)}.join('+')
    end
  end
end

outformat = :csv
if $stdout.isatty
  outformat = :org
end

OptionParser.new do |opts|
  opts.on('--fmt FORMAT') do |fmt|
    outformat = fmt.to_sym
  end
end.parse!

case ARGV.length
when 0
  input = $stdin
when 1
  input = File.open(ARGV[0])
else
  raise "invalid argument count"
end

x = Nokogiri::XML(input)

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

grouped = parts.group_by {|n|
  if n[:bom] && n[:bom] != ""
    n[:bom]
  else
    [n[:bom], n[:footprint], n[:value], n[:place]]
  end
}.values

res = grouped.map do |group|
  namedpart = group.first.dup
  refs = group.map{|n| n[:ref]}
  namedpart[:ref] = refs.sort_by{|s| s.scan(/[\d]+|[^\d]+/).map{|e| /\d+/ === e ? e.to_i : e}}.join(" ")
  namedpart[:count] = refs.count
  namedpart
end

restab = [res.first.keys]
restab += res.map{|n| n.values}

send("print_#{outformat}", restab, $stdout)
