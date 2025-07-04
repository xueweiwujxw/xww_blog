---
title: 'ZeroMQ 代理转发'
date: 2025-07-04T14:46:57+08:00
lastmod: 2025-07-04T14:46:57+08:00
draft: false
author: 'wlanxww'
authorLink: 'https://wlanxww.com'
description: 'ZeroMQ 代理转发'
images: []
tags: ['ZeroMQ', 'proxy']
categories: ['库']
---

**zmq** 代理转发

<!--more-->

## ZeroMQ 模式介绍

> [!NOTE]
>
> 以下描述来自 [Zeromq 文档](https://zguide.zeromq.org/docs/chapter2/#Messaging-Patterns) 机翻

- 请求-回复模式，将一组客户端连接到一组服务。这是一个远程过程调用和任务分发模式。
- 发布-订阅模式，将一组发布者连接到一组订阅者。这是一个数据分发模式。
- 管道模式，以扇出/扇入模式连接节点，可以有多个步骤和循环。这是一个并行任务分发和收集模式。
- 独占对模式，专门连接两个套接字。这是用于连接进程中两个线程的模式，不要与"普通"的套接字对混淆。

> [!NOTE]
>
> 原文
>
> - Request-reply, which connects a set of clients to a set of services. This is a remote procedure call and task distribution pattern.
> - Pub-sub, which connects a set of publishers to a set of subscribers. This is a data distribution pattern.
> - Pipeline, which connects nodes in a fan-out/fan-in pattern that can have multiple steps and loops. This is a parallel task distribution and collection pattern.
> - Exclusive pair, which connects two sockets exclusively. This is a pattern for connecting two threads in a process, not to be confused with “normal” pairs of sockets.

## ZeroMQ **PUB-SUB** 模式

我们主要关注 PUB-SUB 模式。

### 单发布者，多订阅者

最简单的模式是一个发布者，多个订阅者，发布者绑定`socket`、`ipc`或者` inproc`，订阅者连接到对应的端点。

```goat

                         .---------.
                         |Publisher|
                         |---------|
                         |   PUB   |
                          '---+---'
                              |
                     bind to ipc:///tmp/zpub
                              |
      .-----------------------+-----------------------.
     |                        |                        |
  connect                  connect                  connect
     |                        |                        |
 .---+----.               .---+----.               .---+----.
|   SUB    |             |   SUB    |             |   SUB    |
|----------|             |----------|             |----------|
|Subscriber|             |Subscriber|             |Subscriber|
'----------'             '----------'             '----------'
```

### 多发布者，多订阅者

当订阅者需要订阅多个进程的消息时，单发布者模式无法满足，因为 bind 到同一个端点会冲突，zeromq 提供了 xsub 和 xpub 来处理。

```goat

.---------.              .---------.              .---------.
|Publisher|              |Publisher|              |Publisher|
|---------|              |---------|              |---------|
|   PUB   |              |   PUB   |              |   PUB   |
 '---+---'                '---+---'                '---+---'
     |                        |                        |
  connect                  connect                  connect
     |                        |                        |
      '-----------------------+-----------------------'
                              |
                    bind to ipc:///tmp/zxsub
                              |
                           .--+--.
                          |  XSUB |
                          |-------|
                          | Proxy |
                          |-------|
                          |  XPUB |
                           '--+--'
                              |
                    bind to ipc:///tmp/zxpub
                              |
      .-----------------------+-----------------------.
     |                        |                        |
  connect                  connect                  connect
     |                        |                        |
 .---+----.               .---+----.               .---+----.
|   SUB    |             |   SUB    |             |   SUB    |
|----------|             |----------|             |----------|
|Subscriber|             |Subscriber|             |Subscriber|
'----------'             '----------'             '----------'
```

当存在多个发布着的时候，订阅者需要知道接收的消息来自哪个订阅者，有两种简单的思路。

1. 在发送的头部添加自定义字段，可以是字符也可以是数据，双方协商一致即可。
2. 在上述基础上，可以定义`topic`和`msg`消息，`topic`设置为数据标识，类型是字符串，代码可读性更高，`msg`是实际的数据。这要求两者连续发送，可以通过设置`send_flags`为`sndmore`来实现连续发送。

### 实现

> [!TIP]
> zeromq 提供多种语言的 api，下面以 C++为例
>
> [zmq_proxy_exp source code](https://github.com/xueweiwujxw/zmq_proxy_exp)

#### Proxy

> [!TIP] [zmq_proxy.cc](https://github.com/xueweiwujxw/zmq_proxy_exp/blob/main/app/zmq_proxy.cc)

- 分别绑定`XSUB`和`XPUB`，`XSUB`订阅来自实际发布者的消息，`XPUB`订阅`XSUB`的消息，并再次发布

  ```c++
  int main (int argc, char const *argv[])
  {
  	// ...
  	zmq::context_t ctx;

  	// xsub
  	zmq::socket_t xsub_socket(ctx, ZMQ_XSUB);

  	try {
  		xsub_socket.bind(FIXED_ZMQ_XSUB_PATH);
  		logf_info("XSUB bound to %s\n", FIXED_ZMQ_XSUB_PATH);
  	} catch (const std::exception &e) {
  		logf_err("%s\n", e.what());
  		return 1;
  	}

  	// xpub
  	zmq::socket_t xpub_socket(ctx, ZMQ_XPUB);

  	try {
  		xpub_socket.bind(FIXED_ZMQ_XPUB_PATH);
  		xpub_socket.setsockopt(ZMQ_XPUB_VERBOSER, 1);
  		logf_info("XPUB bound to %s\n", FIXED_ZMQ_XPUB_PATH);
  	} catch (const std::exception &e) {
  		logf_err("%s\n", e.what());
  		return 1;
  	}
  	// ...
  }
  ```

- 可选配置，设置`ipc`临时文件的权限，请在确保安全的情况下开放权限

  ```c++
  bool set_ipc_permissions(const char *endpoint)
  {
  	const char *prefix = "ipc://";
  	size_t prefix_len = strlen(prefix);

  	if (strncmp(endpoint, prefix, prefix_len) != 0) {
  		logf_err("Invalid IPC endpoint: %s\n", endpoint);
  		return false;
  	}

  	const char *filepath = endpoint + prefix_len;

  #ifndef _WIN32
  	struct stat st;
  	if (stat(filepath, &st) != 0) {
  		logf_err("IPC file not found: %s (%s)\n", filepath,
  		         strerror(errno));
  		return false;
  	}

  	if (chmod(filepath, S_IRWXU | S_IRWXG | S_IRWXO) != 0) {
  		logf_err("Failed to set permissions for %s: %s\n", filepath,
  		         strerror(errno));
  		return false;
  	}

  	logf_info("Set global permissions for %s\n", filepath);
  #endif

  	return true;
  }

  int main(int argc, char const *argv[])
  {
  	// ...
  	// Optional
  	if (!set_ipc_permissions(FIXED_ZMQ_XSUB_PATH))
  		return 1;
  	if (!set_ipc_permissions(FIXED_ZMQ_XPUB_PATH))
  		return 1;
  	// ...
  }
  ```

- 开启线程处理，提供退出处理

  ```c++
  int main(int argc, char const *argv[])
  {
  	// ...
  	std::thread proxy_thread([&]() {
  		try {
  			logf_info("Starting proxy...\n");
  			zmq::proxy(xsub_socket, xpub_socket);
  		} catch (const zmq::error_t &e) {
  			if (e.num() != ETERM && e.num() != ENOTSOCK)
  				logf_err("Proxy error: %s %d\n", e.what(),
  				         e.num());
  			else
  				logf_info("Proxy terminated normally\n");
  		}
  	});

  	logf_info("Proxy running. Press Ctrl+C to exit...\n");

  	std::unique_lock<std::mutex> lock(sig_mutex);
  	sig_cv.wait(lock);

  	xsub_socket.close();
  	xpub_socket.close();

  	ctx.close();

  	logf_info("Shutting down...\n");

  	proxy_thread.join();

  	logf_info("Clean exit\n");
  	lock.unlock();
  	// ...
  }
  ```

#### Publisher

> [!TIP] [zmq_send.cc](https://github.com/xueweiwujxw/zmq_proxy_exp/blob/main/app/zmq_send.cc)

- 绑定独立的`pub`端点，并连接到`xsub`端点，开启线程发送。发送的`topic`根据线程序号设置

  ```c++
  int main(int argc, char const *argv[])
  {
  	// ...
  	zmq::context_t ctx;

  	std::vector<std::shared_ptr<zmq::socket_t>> pub_sockets;
  	std::vector<std::thread> workers;

  	for (auto i = 0; i < threads; ++i) {
  		zmq::socket_t pub_socket;
  		try {
  			auto pub_socket = std::make_shared<zmq::socket_t>(
  			    zmq::socket_t(ctx, ZMQ_PUB));
  			std::string end_point =
  			    FIXED_ZMQ_PUB_PREFIX + std::to_string(i);
  			pub_socket->bind(end_point);
  			pub_socket->connect(FIXED_ZMQ_XSUB_PATH);

  			logf_info("socket %d bind to %s and connect to %s\n", i,
  			          end_point.c_str(), FIXED_ZMQ_XSUB_PATH);
  			pub_sockets.push_back(pub_socket);
  		} catch (const std::exception &e) {
  			logf_err("%s\n", e.what());
  			return 1;
  		}
  	}

  	logf_info("finish create sockets.\n");

  	for (auto i = 0; i < threads; ++i) {
  		auto pub_socket = pub_sockets[i];
  		workers.emplace_back([pub_socket, i]() {
  			pthread_setname_np(
  			    pthread_self(),
  			    (std::string("zmq_send_test") + std::to_string(i))
  			        .c_str());
  			logf_info("Thread %d started.\n", i);
  			std::string topic_str = "data/" + std::to_string(i);
  			zmq::message_t topic(topic_str);
  			zmq::message_t msg(topic_str);
  			std::vector<char> msg_buffer(1024);
  			std::mutex sig_mutex;
  			while (running) {
  				std::unique_lock<std::mutex> lock(sig_mutex);
  				sig_cv.wait(lock);
  				lock.unlock();

  				auto size = send_num.load();
  				logf_info("Thread %d start sending %d msgs.\n",
  				          i, size);
  				while (size > 0) {
  					int len = snprintf(
  					    msg_buffer.data(),
  					    msg_buffer.size(),
  					    "Thread %d Message %d", i, size);
  					topic.rebuild(topic_str.data(),
  					              topic_str.size());
  					msg.rebuild(msg_buffer.data(), len);
  					try {
  						pub_socket->send(
  						    topic,
  						    zmq::send_flags::sndmore);
  						pub_socket->send(
  						    msg, zmq::send_flags::none);
  					} catch (const zmq::error_t &e) {
  						logf_err("Thread %d Send "
  						         "error: %s\n",
  						         i, e.what());
  					}

  					size--;

  					usleep(40 * 1000);
  				}
  				logf_info("Thread %d finished sending msg.\n",
  				          i);
  			}
  		});
  	}
  	// ...
  }
  ```

#### Subscriber

> [!TIP] [zmq_recv.cc](https://github.com/xueweiwujxw/zmq_proxy_exp/blob/main/app/zmq_recv.cc)

- 连接到`xpub`端点，显示收到的`topic`和`msg`，两者属于独立的数据包

  ```c++
  int main(int argc, char const *argv[])
  {
  	// ...
  	zmq::context_t ctx;

  	zmq::socket_t sub_socket(ctx, ZMQ_SUB);
  	try {
  		sub_socket.setsockopt(ZMQ_SUBSCRIBE, "data", 4);
  		sub_socket.setsockopt(ZMQ_RCVTIMEO, 300);
  		sub_socket.connect(FIXED_ZMQ_XPUB_PATH);
  		logf_info("recv connected to %s\n", FIXED_ZMQ_XPUB_PATH);
  	} catch (const std::exception &e) {
  		logf_err("%s\n", e.what());
  		return 1;
  	}

  	std::thread sub_thread([&]() {
  		zmq::message_t msg;
  		size_t cnt = 0;
  		while (running) {
  			try {
  				auto result = sub_socket.recv(msg);
  				if (result.has_value())
  					printf("%ld - %s\n", ++cnt,
  					       msg.to_string().c_str());
  			} catch (const zmq::error_t &e) {
  				if (e.num() != ETERM)
  					logf_err("Receiver error: %s %d\n",
  					         e.what(), e.num());
  				else
  					logf_info(
  					    "Receiver terminated normally\n");
  			}
  		}
  	});

  	logf_info("Recving running. Press Ctrl+C to exit...\n");

  	std::unique_lock<std::mutex> lock(sig_mutex);
  	sig_cv.wait(lock);

  	logf_info("Shutting down...\n");

  	sub_thread.join();

  	sub_socket.close();
  	ctx.close();

  	logf_info("Clean exit\n");
  	lock.unlock();
  	// ...
  }
  ```
