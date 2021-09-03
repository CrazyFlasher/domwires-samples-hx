package com.domwires.ext.service.net.impl;

import com.domwires.core.factory.AppFactory;
import com.domwires.core.factory.IAppFactory;
import com.domwires.ext.service.net.impl.NodeNetServerService;
import com.domwires.ext.service.net.server.INetServerService;
import com.domwires.ext.service.net.server.NetServerServiceMessageType;
import js.node.http.ClientRequest;
import js.node.http.Method;
import js.node.Http;
import js.node.net.Socket;
import js.node.Net;
import utest.Assert;
import utest.Async;
import utest.Test;

class WebServerServiceTest extends Test
{
    private var factory:IAppFactory;
    private var service:INetServerService;

    public function setupClass():Void {}

    public function teardownClass():Void {}

    public function setup():Void
    {
        factory = new AppFactory();
        factory.mapToType(INetServerService, NodeNetServerService);
        factory.mapClassNameToValue("String", "127.0.0.1", "INetServerService_httpHost");
        factory.mapClassNameToValue("String", "127.0.0.1", "INetServerService_tcpHost");
        factory.mapClassNameToValue("Int", 3000, "INetServerService_httpPort");
        factory.mapClassNameToValue("Int", 3001, "INetServerService_tcpPort");
    }

    @:timeout(5000)
    public function teardown(async:Async):Void
    {
        var httpClosed:Bool = !service.getIsOpened(ServerType.Http);
        var tcpClosed:Bool = !service.getIsOpened(ServerType.Tcp);

        var complete:Void->Void = () ->
        {
            service.dispose();
            async.done();
        };

        service.addMessageListener(NetServerServiceMessageType.TcpClosed, m ->
        {
            tcpClosed = true;

            if (httpClosed)
            {
                complete();
            }
        });

        service.addMessageListener(NetServerServiceMessageType.HttpClosed, m ->
        {
            httpClosed = true;

            if (tcpClosed)
            {
                complete();
            }
        });

        service.close();
    }

    @:timeout(5000)
    public function testClose(async:Async):Void
    {
        var httpClosed:Bool = false;
        var tcpClosed:Bool = false;

        service = factory.getInstance(INetServerService);
        service.addMessageListener(NetServerServiceMessageType.HttpClosed, m ->
        {
            httpClosed = true;

            Assert.isFalse(service.getIsOpened(ServerType.Http));

            service.close(ServerType.Tcp);

            if (tcpClosed)
                async.done();
        });

        service.addMessageListener(NetServerServiceMessageType.TcpClosed, m ->
        {
            tcpClosed = true;

            Assert.isFalse(service.getIsOpened(ServerType.Tcp));

            if (httpClosed)
                async.done();
        });

        service.close(ServerType.Http);
    }

    @:timeout(5000)
    public function testHandlerHttpPostRequest(async:Async):Void
    {
        var data:String = "Dummy request";
        var options:HttpRequestOptions = {
            hostname: "localhost",
            method: Method.Post,
            port: 3000,
            path: "/test",
            headers: {
                'Content-Type': 'application/json',
                'Content-Length': Std.string(data.length)
            }
        };

        service = factory.getInstance(INetServerService);
        service.startListen({id: "/test", type: RequestType.Post});
        service.addMessageListener(NetServerServiceMessageType.GotHttpRequest, m ->
        {
            var requestData:String = service.requestData;
            Assert.equals(data, requestData);
            async.done();
        });

        var req:ClientRequest = Http.request(options);
        req.write(data);
        req.end();
    }

    @:timeout(5000)
    public function testHandlerHttpGetRequest(async:Async):Void
    {
        var data:String = "Dummy request";
        var options:HttpRequestOptions = {
            hostname: "localhost",
            method: Method.Get,
            port: 3000,
            path: "/test",
            headers: {
                'Content-Type': 'application/json',
                'Content-Length': Std.string(data.length)
            }
        };

        service = factory.getInstance(INetServerService);
        service.startListen({id: "/test", type: RequestType.Get});
        service.addMessageListener(NetServerServiceMessageType.GotHttpRequest, m ->
        {
            var requestData:String = service.requestData.toString();
            Assert.equals(data, requestData);
            async.done();
        });

        var req:ClientRequest = Http.request(options);
        req.write(data);
        req.end();
    }

    @:timeout(5000)
    public function testHandlerHttpGetRequestWithQueryParams(async:Async):Void
    {
        var options:HttpRequestOptions = {
            hostname: "localhost",
            method: Method.Get,
            port: 3000,
            path: "/test?param_1=preved&param_2=boga"
        };

        service = factory.getInstance(INetServerService);
        service.startListen({id: "/test", type: RequestType.Get});
        service.addMessageListener(NetServerServiceMessageType.GotHttpRequest, m ->
        {
            Assert.equals(service.getQueryParam("param_1"), "preved");
            Assert.equals(service.getQueryParam("param_2"), "boga");
            async.done();
        });

         Http.request(options).end();
    }

    @:timeout(5000)
    public function testHandlerTcpConnect(async:Async):Void
    {
        service = factory.getInstance(INetServerService);
        service.addMessageListener(NetServerServiceMessageType.ClientConnected, m ->
        {
            Assert.isTrue(true);
            async.done();
        });

        Net.connect({port: 3001, host: "127.0.0.1"}).end();
    }

    @:timeout(50000)
    public function testHandlerTcpRequest(async:Async):Void
    {
        service = factory.getInstance(INetServerService);

        var client:Socket = null;
        client = Net.connect({port: 3001, host: "127.0.0.1"}, () ->
        {
            var jsonString:String = "";
            for (i in 0...1000)
            {
                jsonString += "{\"firstName\": \"Anton\", \"lastName\": \"Nefjodov\", \"age\": 35},";
            }
            jsonString = jsonString.substring(0, jsonString.length - 1);
            jsonString = "{\"people\":[" + jsonString + "]}\n";

            client.write(jsonString);
        });

        service.addMessageListener(NetServerServiceMessageType.GotTcpData, m ->
        {
            var requestData:String = service.requestData;
            Assert.equals("Anton", haxe.Json.parse(requestData).people[0].firstName);
            client.end();
            async.done();
        });
    }
}
