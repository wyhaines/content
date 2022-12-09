# It's a Ruby/Crystal/Rust [Advent of Code 2022 - Day 1](https://adventofcode.com/2022/day/1)

Welcome to my Advent of Code adventure for 2022! This year, I am going to solve the Advent of Code challenges using three different languages - Ruby, Crystal, and Rust. The goal is not to golf for the most terse answer in each language, but rather to implement reasonably idiomatic, but conceptually similar solutions in each language, and to use that as a tool to compare and contrast the languages. So, without further adieu, let's get started!

## Part 1

To see the full details of the challenge, visit the [Advent of Code 2022 - Day 1](https://adventofcode.com/2022/day/1) page. However, the tl;dr version of the challenge is as follows:

> In this puzzle, a group of Elves are going on an expedition to collect star fruit for Santa's reindeer. Each Elf is carrying food items with different numbers of calories. The puzzle is to determine which Elf is carrying the most calories and how many total calories they are carrying. The calories of each food item are listed in a sequence of numbers, with a blank line separating the inventory of each Elf. To solve the puzzle, the numbers must be read and the total calories for each Elf must be calculated. The Elf with the highest total calories is the answer to the puzzle.

So, for example, given the following input:

```
1000
2000
3000

4000

5000
6000

7000
8000
9000

10000
```

The fourth elf would be carrying 24000 calories, and that would be the answer to this puzzle.

### The Approach

The task is to read the input, delimited by the blank lines, and then sum the numbers in each chunk. This is pretty straight forward in Ruby, and so this first solution is going to be presented as a short, imperative solution in order to ease into this process.

#### Ruby solution

The Ruby solution that I wrote looks like this:

```ruby
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
```

This solution assumes that the input is in a file called `input.txt`. That file is read into memory, and then split into chunks delimited by repeated newlines (i.e. a blank line).

The resulting array is then mapped, splitting each chunk into an array of text lines, which are then converted, via `map(&:to_i)`, into an array of integers.

At this point, the program holds an array of arrays of integers. The next step is to sum each of the inner arrays, and then to find the maximum of those sums. This is done via the `map(&:sum).max` method calls.

#### Crystal solution

For this first task, the Crystal solution is nearly identical to the Ruby solution:

```crystal
the_most_calories = File.read("input.txt")
  .split(/\n\n/m)
  .map do |group|
    group
      .strip
      .split(/\n/)
      .map(&.to_i)
  end
  .map(&.sum)
  .max

puts the_most_calories
```

The only difference is that the `&.` is used instead of the `&:` syntax for the `map` method calls, and double quotes are used around the filename instead of single quotes.

#### Rust solution

The Rust solution is conceptually identical to the Ruby and Crystal solutions, but the syntax is a bit different:

```rust
use std::fs;

fn parse_and_search_calories(filename: &str) -> i32 {
    let text = fs::read_to_string(filename).unwrap();

    text.split("\n\n")
        .map(|group| {
            group
                .trim()
                .split("\n")
                .map(|line| line.parse::<i32>().unwrap())
        })
        .map(|numbers| numbers.sum())
        .max().unwrap()
}

fn main() {
    print!("{}\n", parse_and_search_calories("input.txt"));
}
```

The most interesting aspect to solving this with Rust was just how similar the Rust solution ended up being to the Ruby and the Crystal solutions. Rust is more verbose, it requires more ceremony, and its compiler's type inference requires more explicit type annotations than Crystal requires, but the overall structure of the solution is very similar to the other two.

The `parse_and_search_calories` function is used to read the input file, split it into chunks delimited by repeated newlines, and then to map each chunk into an array of integers. The `map` method calls are used to convert the text lines into integers, and then to sum the integers in each chunk. The `max` method call is used to find the maximum of the sums. The `unwrap` method calls are used to unwrap the `Result` values returned by the `read_to_string`, `parse`, and `max` methods.

The `main` function is used to call the `parse_and_search_calories` function, and then to print the result.

## Part 2

The second part of the puzzle involves expanding the search to find the top three elves with the most calories, and then to sum the number of calories that the top three are carrying. This turned out to be just a minor variation on the solution for part 1.

### The Approach

The approach to solving this is identical to part 1, except that instead of finding the `max` of the list, the final list should first be sorted, and the highest three values selected and summed.

#### Ruby solution

```ruby
the_most_calories = File.read('input.txt')
                        .split(/\n\n/m)
                        .map do |group|
  group
    .strip
    .split(/\n/)
    .map(&:to_i)
end
                        .map(&:sum)
                        .sort
                        .last(3)

puts the_most_calories.inspect
puts the_most_calories.sum
```

The only difference is that the `sort` method is used to sort the list of sums, and then the `last(3)` method is used to select the last three elements of the list.

#### Crystal solution

```crystal
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
```

Again, the only difference is that the `sort` method is used to sort the list of sums, and then the `last(3)` method is used to select the last three elements of the list.

#### Rust solution

```rust
use std::fs;

fn parse_and_search_calories(filename: &str) -> Vec<i32> {
    let text = fs::read_to_string(filename).unwrap();

    let mut numbers: Vec<i32> = text
        .split("\n\n")
        .map(|group| {
            group
                .trim()
                .split("\n")
                .map(|line| line.parse::<i32>().unwrap())
                .sum()
        })
        .collect::<Vec<_>>();

    numbers.sort_by(|a, b| b.cmp(a));
    numbers.truncate(3);
    numbers
}

fn main() {
    let top_calories = parse_and_search_calories("input.txt");
    let sum_calories = top_calories.iter().sum::<i32>();
    print!("{:?}\n{}\n", top_calories, sum_calories);
}
```

The only real difference is that the `sort_by` method is used to sort the list of sums, and then the `truncate` method is used to select the last three elements of the list.

## Conclusion

This was a fun puzzle, and it served as a good introduction to the general ways in which conceptually similar code can vary between the chosen languages, and particularly between Rust and the other two languages. The key differences with the Rust version were the need to explicitly annotate the types of the variables, and the need to explicitly unwrap the `Result` values returned by several of the methods, but the solutions were otherwise quite similar across all three languages.