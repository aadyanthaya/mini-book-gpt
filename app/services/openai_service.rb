require "tokenizers"
require "cosine_similarity"
require "openai"

class OpenaiService
  def initialize
    @tokenizer = Tokenizers.from_pretrained("gpt2")
    @openai_client = OpenAI::Client.new(access_token: ENV["OPENAI_TOKEN"])
  end

  def get_answer(question)
    begin
      question_embedding = get_question_embedding(question)
      vector_similarity = get_vector_similarity(question_embedding)
      chosen_sections = get_choosen_section(vector_similarity).join(SEPARATOR)

      prompt = construct_prompt(question, chosen_sections)

      response = @openai_client.completions(
        parameters: {
          model: "text-davinci-003",
          prompt: prompt,
          max_tokens: 150,
          temperature: 0
        }
      )

      answer = response["choices"][0]["text"]

      return { answer: answer, context: chosen_sections }
    rescue StandardError => e
      puts "Error: #{e.message}"
      return { error: e.message }
    end
  end

  private
  def get_question_embedding(question)
    response = @openai_client.embeddings(
      parameters: {
        model: "text-embedding-ada-002",
        input: question
      }
    )

    question_embedding = response["data"][0]["embedding"]
    return question_embedding
  end

  private
  def get_vector_similarity(question_embedding)
    similarity_array = []

    CSV.foreach("embeddings.csv", headers: true) do |row|
      text_embedding =  JSON.parse(row["Embedding"])
      score = cosine_similarity(question_embedding, text_embedding)

      similarity_array << { 
        "text" => row["Text"],
        "similarity_score" => score,
        "tokens" => row["Tokens"].to_i { 0 }
      }
    end

    similarity_array_filtered = similarity_array.reject { |item| item["similarity_score"].nil? }
    return similarity_array_filtered.sort_by { |item| -item["similarity_score"] }
  end

  private
  def get_choosen_section(vector_similarity)
    chosen_sections = []
    chosen_sections_len = 0
    separator_len = 3
    
    vector_similarity.each do |item|
      text = item["text"]
      tokens = item["tokens"]
      encoded_text_ids = @tokenizer.encode(text).ids

      tmp_count =  tokens + separator_len
      
      if chosen_sections_len + tmp_count > MAX_SECTION_LEN
        space_left =  MAX_SECTION_LEN - chosen_sections_len - separator_len
        sliced_text_ids = encoded_text_ids.take(space_left)
        chosen_sections << @tokenizer.decode(sliced_text_ids)
        break
      end

      chosen_sections_len += tmp_count
      chosen_sections << text
    end

    return chosen_sections
  end

  private
  def construct_prompt(question, sections)
    q_and_a_string = ""

    QUESTIONS.each do |q|
        q_and_a_string += "\n\n\nQ: #{q[:question]}\n\nA: #{q[:answer]}"
    end
    
    return HEADER + sections + q_and_a_string + "\n\n\nQ: " + question + "\n\nA: "
  end
end
