the_most_calories = File.read("input.txt")
  .split(/\n\n/m)
  .map do |group|
    group
      .strip
      .split(/\n/)
      .map(&.to_i)
  end
  .map(&.sum)
  .sort
  .last(3)

puts the_most_calories.inspect
puts the_most_calories.sum
