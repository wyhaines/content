class RuckSackn
  def initialize(filename)
    rucksacks = parse_rucksacks(filename)
    sum = rucksacks.map { |rucksack| item_priority(find_duplicates(*rucksack)) }.sum

    puts "Priority sum of all duplicated items: #{sum}"
  end

  def parse_rucksacks(filename)
    File.read(filename).split("\n").map do |line|
      middle = line.size // 2
      left = line[0..(middle - 1)]
      right = line[middle..]
      {left, right}
    end
  end

  # The instructions are ambiguous about whether or not there may be more than one duplicate,
  # so this code and the code in `item_priority` can handle any number of duplicates.
  def find_duplicates(left, right)
    left.split("") & right.split("")
  end

  def item_priority(items)
    items.reduce(0) do |sum, item|
      character = item[0]?
      if character
        case character
        when ('a'..'z')
          sum += character.ord - 96
        when ('A'..'Z')
          sum += character.ord - 38
        end
      end

      sum
    end
  end
end

RuckSackn.new(ARGV[0]? || "input.txt")
