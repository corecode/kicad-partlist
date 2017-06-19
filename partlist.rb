require 'nokogiri'
require 'optparse'

class Part
  def initialize(node)
    @n = node
  end

  def [](x)
    case x.downcase
    when 'ref'
      @n.xpath('@ref').to_s
    when 'value'
      @n.xpath('value/text()').to_s
    when 'footprint'
      @n.xpath('substring-after(footprint/text(), ":")').to_s
    else
      @n.xpath("fields/field[@name=\"#{x}\"]/text()").to_s
    end
  end

  def fields
    fields = @n.xpath('fields/field/@name').map(&:to_s)
    ['Ref', 'Value', 'Footprint'] + fields
  end
end

def print_csv(ary, dest)
  ary.map do |row|
    l = row.map do |col|
      if /["',\\]/ === col
        col = '"%s"' % col.gsub(/[\\"]/, '\\\1')
      end
      col
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

do_group = true
outformat = :csv
if $stdout.isatty
  outformat = :org
end

OptionParser.new do |opts|
  opts.on('--fmt FORMAT') do |fmt|
    outformat = fmt.to_sym
  end
  opts.on('--long') do
    do_group = false
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

parts = x.xpath('//export/components/comp').map{|p| Part.new(p)}
  # {
  #   count: '',
  #   value: n.xpath('value/text()').to_s,
  #   footprint: n.xpath('substring-after(footprint/text(), ":")').to_s,
  #   bom: n.xpath('fields/field[@name="BOM"]/text()').to_s,
  #   place: n.xpath('fields/field[@name="Place"]/text()').to_s,
  #   ref: n.xpath('@ref').to_s,
  # }

parts.select!{|p| !['nopart'].include?(p['Place'].downcase)}

fields = parts.map{|p| p.fields}.flatten.uniq
parttab = parts.map{|n| fields.map{|f| n[f]}}

def collect(row, keys, fields)
  result = []
  keys.each do |k|
    idx = fields.find_index(k)
    next if !idx
    result << row[idx]
  end
  result
end

grouped = parttab.group_by {|n|
  partno = collect(n, ['Part Number', 'BOM', 'Manufacturer'], fields) - ['']
  if !partno.empty?
    partno
  else
    collect(n, fields - ['Ref'], fields)
  end
}.values

refidx = fields.find_index('Ref')
groupedtab = grouped.map do |group|
  namedpart = group.first.dup
  refs = group.map{|n| n[refidx]}
  ref = refs.sort_by{|s| s.scan(/[\d]+|[^\d]+/).map{|e| /\d+/ === e ? e.to_i : e}}.join(" ")
  noplace = group.select{|n| collect(n, ['Place'], fields) == ['DNP']}
  namedpart[refidx] = ref
  namedpart.insert(refidx+1, refs.count - noplace.count)
  namedpart
end


if do_group
  fields.insert(refidx+1, 'Count')
  restab = [fields]
  restab += groupedtab
else
  restab = [fields]
  restab += parttab
end

send("print_#{outformat}", restab, $stdout)
