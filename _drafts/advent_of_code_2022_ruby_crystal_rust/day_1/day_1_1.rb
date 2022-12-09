the_most_calories = File.read('input.txt')
                        .split(/\n\n/m)
                        .map do |group|
  group
    .strip
    .split(/\n/)
    .map(&:to_i)
end
                        .map(&:sum)
                        .max

puts the_most_calories
