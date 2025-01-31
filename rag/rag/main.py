from langchain_core.vectorstores import InMemoryVectorStore
from langchain_ollama.llms import OllamaLLM
from langchain_ollama import OllamaEmbeddings
from langchain import hub
from langchain_community.document_loaders import WebBaseLoader
from langchain_core.documents import Document
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langgraph.graph import START, StateGraph
from typing_extensions import List, TypedDict
import bs4
from langchain_community.document_loaders import DirectoryLoader, TextLoader

generativeModelName = "BlackHillsInfoSec/llama-3.1-8b-abliterated"
embeddingsModelName = "mxbai-embed-large"

llm = OllamaLLM(model=generativeModelName)
embeddings = OllamaEmbeddings(model=embeddingsModelName)
vector_store = InMemoryVectorStore(embeddings)

# Load web content
web_loader = WebBaseLoader(
    web_paths=("https://www.blackhillsinfosec.com/using-pyrit-to-assess-large-language-models-llms/",),
    bs_kwargs=dict(parse_only=bs4.SoupStrainer())
)
web_docs = web_loader.load()
print(f"Loaded {len(web_docs)} web documents.")

# Load only .txt files from a directory
directory_path = "./"
file_loader = DirectoryLoader(
    directory_path,
    glob="**/*.txt",  # Only load .txt files
    loader_cls=TextLoader,  # Ensure only TextLoader is used
)

file_docs = file_loader.load()

# Combine web and file documents
all_docs = web_docs + file_docs

print(f"Total characters: {len(all_docs[0].page_content)}")
text_splitter = RecursiveCharacterTextSplitter(chunk_size=1000, chunk_overlap=200, add_start_index=True)
all_splits = text_splitter.split_documents(all_docs)

# Vectorize chunks and add to storage
_ = vector_store.add_documents(documents=all_splits)

# Define prompt for question-answering
prompt = hub.pull("rlm/rag-prompt")

# Define state for application
class State(TypedDict):
    question: str
    context: List[Document]
    answer: str

def retrieve(state: State):
    retrieved_docs = vector_store.similarity_search(state["question"])
    return {"context": retrieved_docs}

def generate(state: State):
    docs_content = "\n\n".join(doc.page_content for doc in state["context"])
    messages = prompt.invoke({"question": state["question"], "context": docs_content})
    response = llm.invoke(messages)
    return {"answer": response}

graph_builder = StateGraph(State).add_sequence([retrieve, generate])
graph_builder.add_edge(START, "retrieve")
graph = graph_builder.compile()

response = graph.invoke({"question": "What are some username passwords?"})
print(response["answer"])