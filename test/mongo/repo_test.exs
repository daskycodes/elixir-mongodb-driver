defmodule Mongo.RepoTest do
  use ExUnit.Case

  defmodule MyRepo do
    use Mongo.Repo,
      topology: :mongo,
      otp_app: :mongodb_driver
  end

  defmodule Post do
    use Mongo.Collection

    collection "posts" do
      attribute :title, String.t()
    end
  end

  setup do
    assert {:ok, pid} = start_supervised({Mongo, MyRepo.config()})
    Mongo.drop_database(pid)
    {:ok, [pid: pid]}
  end

  describe "config/0" do
    test "returns the defined application configuration" do
      assert [
               name: :mongo,
               url: "mongodb://127.0.0.1:27017/mongodb_test",
               show_sensitive_data_on_connection_error: true
             ] = MyRepo.config()
    end
  end

  describe "get/3" do
    test "returns a single document for the given bson id" do
      {:ok, %{inserted_id: id}} = Mongo.insert_one(:mongo, "posts", %{title: "Hello World"})

      assert %Post{title: title} = MyRepo.get(Post, id)
      assert title == "Hello World"
    end

    test "returns nil if the document is not found" do
      assert MyRepo.get(Post, "doesnotexist") == nil
    end
  end

  describe "get_by/3" do
    test "returns a single document for the given filter" do
      {:ok, _insert_one_result} = Mongo.insert_one(:mongo, "posts", %{title: "Hello World"})

      assert %Post{title: title} = MyRepo.get_by(Post, %{title: "Hello World"})
      assert title == "Hello World"
    end

    test "filters case insensitive with collation option" do
      {:ok, _insert_one_result} = Mongo.insert_one(:mongo, "posts", %{title: "Hello World"})

      assert %Post{title: title} = MyRepo.get_by(Post, %{title: "hello world"}, collation: %{locale: "en", strength: 2})
      assert title == "Hello World"
    end

    test "returns nil if the document is not found" do
      assert MyRepo.get_by(Post, %{title: "doesnotexist"}) == nil
    end
  end

  describe "all/3" do
    test "returns all documents for the given collection" do
      posts = for n <- 0..4, do: %{title: "test #{n}"}
      {:ok, _insert_many_result} = Mongo.insert_many(:mongo, "posts", posts)

      assert posts = MyRepo.all(Post)
      assert length(posts) == 5

      for {post, index} <- Enum.with_index(posts) do
        assert post.title == "test #{index}"
      end
    end

    test "returns all documents for the given filter" do
      some = for _n <- 0..4, do: %{title: "some"}
      none = for _n <- 0..4, do: %{title: "none"}
      {:ok, _insert_many_result} = Mongo.insert_many(:mongo, "posts", some ++ none)

      assert posts = MyRepo.all(Post, %{title: "some"})
      assert length(posts) == 5

      assert posts = MyRepo.all(Post, %{title: "none"})
      assert length(posts) == 5
    end

    test "returns the amount of documents for the given limit option" do
      posts = for _n <- 0..4, do: %{title: "test"}
      {:ok, _insert_many_result} = Mongo.insert_many(:mongo, "posts", posts)

      assert posts = MyRepo.all(Post, %{}, limit: 2)
      assert length(posts) == 2
    end

    test "returns an empty list when there are no documents" do
      assert [] = MyRepo.all(Post)
    end
  end

  describe "stream/3" do
    test "returns all documents for the given collection in a stream" do
      posts = for n <- 0..4, do: %{title: "test #{n}"}
      {:ok, _insert_many_result} = Mongo.insert_many(:mongo, "posts", posts)

      assert posts = MyRepo.stream(Post)
      assert is_struct(posts, Stream)

      for {post, index} <- Enum.with_index(posts) do
        assert post.title == "test #{index}"
      end
    end

    test "returns all documents for the given filter in a stream" do
      some = for _n <- 0..4, do: %{title: "some"}
      none = for _n <- 0..4, do: %{title: "none"}
      {:ok, _insert_many_result} = Mongo.insert_many(:mongo, "posts", some ++ none)

      assert posts = MyRepo.stream(Post, %{title: "some"})
      assert is_struct(posts, Stream)
      assert posts |> Enum.to_list() |> length() == 5

      assert posts = MyRepo.stream(Post, %{title: "none"})
      assert is_struct(posts, Stream)
      assert posts |> Enum.to_list() |> length() == 5
    end

    test "returns the amount of documents for the given limit option" do
      posts = for _n <- 0..4, do: %{title: "test"}
      {:ok, _insert_many_result} = Mongo.insert_many(:mongo, "posts", posts)

      assert posts = MyRepo.stream(Post, %{}, limit: 2)
      assert is_struct(posts, Stream)
      assert posts |> Enum.to_list() |> length() == 2
    end

    test "returns an empty stream when there are no documents" do
      assert [] =
               Post
               |> MyRepo.stream()
               |> Enum.to_list()
    end
  end

  describe "aggregate/3" do
    test "returns all documents for the aggregation pipeline" do
      posts = for letter <- ["a", "b", "c", "d"], do: %{title: letter}
      {:ok, _insert_many_result} = Mongo.insert_many(:mongo, "posts", posts)

      assert posts =
               MyRepo.aggregate(Post, [
                 %{"$sort" => [{"title", -1}]},
                 %{"$limit" => 2}
               ])

      assert [%{title: "d"}, %{title: "c"}] = posts
    end

    test "returns an empty list if the aggregation pipeline does not have any results" do
      assert [] = MyRepo.aggregate(Post, [])
    end
  end

  describe "count/3" do
    test "returns the count of documents for the given filter" do
      some = for _n <- 0..4, do: %{title: "some"}
      none = for _n <- 0..4, do: %{title: "none"}
      {:ok, _insert_many_result} = Mongo.insert_many(:mongo, "posts", some ++ none)

      assert {:ok, 10} = MyRepo.count(Post)
      assert {:ok, 5} = MyRepo.count(Post, %{title: "some"})
      assert {:ok, 5} = MyRepo.count(Post, %{title: "none"})
      assert {:ok, 0} = MyRepo.count(Post, %{title: "zero"})
    end

    test "returns the count of documents for the given filter and options" do
      posts = for _n <- 0..4, do: %{title: "test"}
      {:ok, _insert_many_result} = Mongo.insert_many(:mongo, "posts", posts)

      assert {:ok, 2} = MyRepo.count(Post, %{title: "test"}, limit: 2)
    end
  end

  describe "exists?/2" do
    test "returns whether a document for the given filter exists" do
      {:ok, _insert_one_result} = Mongo.insert_one(:mongo, "posts", %{title: "test"})

      assert MyRepo.exists?(Post)
      assert MyRepo.exists?(Post, %{title: "test"})
      refute MyRepo.exists?(Post, %{title: "doesnotexist"})
    end
  end

  describe "update_all/4" do
    test "applies the updates to the all documents of the given collection" do
      posts = for _n <- 0..4, do: %{title: "test"}
      {:ok, _insert_many_result} = Mongo.insert_many(:mongo, "posts", posts)

      assert {:ok, %{modified_count: 5}} = MyRepo.update_all(Post, %{}, %{"$set" => %{title: "updated"}})
      assert {:ok, 5} = MyRepo.count(Post, %{title: "updated"})
      assert {:ok, 0} = MyRepo.count(Post, %{title: "test"})
    end

    test "applies the updates to the all documents for the given filter" do
      some = for _n <- 0..4, do: %{title: "some"}
      none = for _n <- 0..4, do: %{title: "none"}
      {:ok, _insert_many_result} = Mongo.insert_many(:mongo, "posts", some ++ none)

      assert {:ok, %{modified_count: 5}} = MyRepo.update_all(Post, %{title: "some"}, %{"$set" => %{title: "updated"}})
      assert {:ok, 5} = MyRepo.count(Post, %{title: "updated"})
      assert {:ok, 0} = MyRepo.count(Post, %{title: "some"})
      assert {:ok, 5} = MyRepo.count(Post, %{title: "none"})
    end
  end

  describe "delete_all/3" do
    test "deletes all documents of the given collection" do
      posts = for _n <- 0..4, do: %{title: "test"}
      {:ok, _insert_many_result} = Mongo.insert_many(:mongo, "posts", posts)

      assert {:ok, %{deleted_count: 5}} = MyRepo.delete_all(Post)
      assert {:ok, 0} = MyRepo.count(Post, %{title: "test"})
    end

    test "deletes all documents for the given filter" do
      some = for _n <- 0..4, do: %{title: "some"}
      none = for _n <- 0..4, do: %{title: "none"}
      {:ok, _insert_many_result} = Mongo.insert_many(:mongo, "posts", some ++ none)

      assert {:ok, %{deleted_count: 5}} = MyRepo.delete_all(Post, %{title: "some"})
      assert {:ok, 0} = MyRepo.count(Post, %{title: "some"})
      assert {:ok, 5} = MyRepo.count(Post, %{title: "none"})
    end
  end

  describe "fetch/3" do
    test "returns a single document for the given bson id" do
      {:ok, %{inserted_id: id}} = Mongo.insert_one(:mongo, "posts", %{title: "Hello World"})

      assert {:ok, %Post{title: title}} = MyRepo.fetch(Post, id)
      assert title == "Hello World"
    end

    test "returns an error tuple if the document is not found" do
      assert {:error, :not_found} = MyRepo.fetch(Post, "doesnotexist")
    end
  end

  describe "fetch_by/3" do
    test "returns a single document for the given filter" do
      {:ok, _insert_one_result} = Mongo.insert_one(:mongo, "posts", %{title: "Hello World"})

      assert {:ok, %Post{title: title}} = MyRepo.fetch_by(Post, %{title: "Hello World"})
      assert title == "Hello World"
    end

    test "filters case insensitive with collation option" do
      {:ok, _insert_one_result} = Mongo.insert_one(:mongo, "posts", %{title: "Hello World"})

      assert {:ok, %Post{title: title}} = MyRepo.fetch_by(Post, %{title: "hello world"}, collation: %{locale: "en", strength: 2})
      assert title == "Hello World"
    end

    test "returns an error tuple if the document is not found" do
      assert {:error, :not_found} = MyRepo.fetch_by(Post, %{title: "doesnotexist"})
    end
  end

  describe "insert/2" do
    test "inserts a new document" do
      {:ok, %Post{title: "test"}} =
        Post.new()
        |> Map.put(:title, "test")
        |> MyRepo.insert()
    end
  end

  describe "insert!/2" do
    test "inserts a new document" do
      %Post{title: "test"} =
        Post.new()
        |> Map.put(:title, "test")
        |> MyRepo.insert!()
    end
  end

  describe "update/1" do
    test "updates a document" do
      {:ok, post} =
        Post.new()
        |> Map.put(:title, "test")
        |> MyRepo.insert()

      {:ok, %Post{title: "updated"}} =
        post
        |> Map.put(:title, "updated")
        |> MyRepo.update()
    end
  end

  describe "update!/1" do
    test "updates a document" do
      {:ok, post} =
        Post.new()
        |> Map.put(:title, "test")
        |> MyRepo.insert()

      %Post{title: "updated"} =
        post
        |> Map.put(:title, "updated")
        |> MyRepo.update!()
    end
  end
end
